# FTP/SFTP Connection Management Theory & Netty Lifecycle

## Engineering Reference: Connection Lifecycle & Resource Management

---

## Part 1: FTP Server Theory

### The Passive Mode Problem

**Source:** Fox, Richard, and Wei Hao. *Internet Infrastructure: Networking, Web Services, and Cloud Computing*. CRC Press, 2018, pp. 83-84.

FTP uses **two separate TCP connections**:

```
Control Connection (persistent)
     │
     ├── Client sends: "I want file X"
     │
     └── Server responds: "Connect to me on port 3851 for data"

Data Connection (ephemeral)
     │
     └── Client opens NEW connection to port 3851
```

**Critical issue in passive mode:**
The server tells the client to open a *second* connection. Both connections are now **independent TCP sessions** that must be managed separately.

**From Fox & Hao, *Internet Infrastructure* (2018), pp. 83-84:**
> "the server sent back a port number. Once received, the client is now responsible for opening a data connection to the server. It will do so by using the next consecutive port sent by its own OS and will request the port number sent in the previous message from the server."

> "That is, in passive mode, port 20 is not used for data, but instead, the port number that the server sent is used."

### Why This Matters

**Source:** Fox & Hao, *Internet Infrastructure*, pp. 83-84.

In active mode, the server controls both connections. In passive mode:
- Client initiates both connections
- Server must track TWO sockets per session
- If either connection cleanup fails, resources leak
- **Control connection can persist while data connection is abandoned**

This is the foundation of the zombie connection problem.

---

## Part 2: Netty's Selector Pattern (Documented Behavior)

### What a Selector Does

From Java NIO (which Netty wraps):

```
Selector
    │
    ├── Monitors multiple sockets
    ├── Checks readiness: OP_READ, OP_WRITE, OP_CONNECT
    └── Returns "ready" sockets to process
```

**Key constraint:** A selector can only monitor **registered** channels. Registration is explicit.

### EventLoop Architecture

Netty's [EventLoop](https://netty.io/4.1/api/io/netty/channel/EventLoop.html) is a thread that:

1. **Selects** - Calls `Selector.select()` to find ready channels
2. **Processes I/O** - Handles data from ready channels  
3. **Runs tasks** - Executes queued work
4. **Repeats**

Each EventLoop has one thread. Each Selector monitors N channels.

**Structure:**
```
EventLoopGroup (thread pool)
    │
    ├── EventLoop (Thread 1)
    │       └── Selector → monitors Channel set A
    │
    ├── EventLoop (Thread 2)
    │       └── Selector → monitors Channel set B
    │
    └── EventLoop (Thread N)
            └── Selector → monitors Channel set N
```

**Reference:** [NioEventLoopGroup API](https://netty.io/4.1/api/io/netty/channel/nio/NioEventLoopGroup.html)

### The Polling Cost

The selector must iterate over **all registered channels** on every select cycle. 

From the documentation:
> "When you deregister a Channel it basically removed itself from the servicing Thread which in the case of NIO also is the Selector itself. This means you will not get notified on any event changes."

**Implication:** If a channel is registered but inactive, the selector still polls it. The channel consumes CPU cycles for no productive work.

---

## Part 3: Channel Lifecycle States (Netty 4.x)

### Documented Lifecycle Events

From [Channel API documentation](https://netty.io/4.0/api/io/netty/channel/Channel.html):

```
1. Channel created
2. channelRegistered()    ← Added to EventLoop/Selector
3. channelActive()        ← Socket connected
4. [I/O operations]
5. channelInactive()      ← Socket closed
6. channelUnregistered()  ← Removed from EventLoop/Selector
7. Channel destroyed
```

**Critical distinction:**
- **close()** - Closes the socket (step 5)
- **deregister()** - Removes from Selector (step 6)

### The Gap Between Close and Deregister

From StackOverflow discussion (Netty maintainers):
> "I have noticed that the future returned by channel.close() is completed once the underlying socket is closed, **before the pipeline is deregistered** and the handlers are removed from it."

**What this means:**
1. Socket closes (no more data transfer possible)
2. **BUT** channel still registered with Selector
3. Selector keeps polling the dead channel
4. Eventually deregister() is called to clean up

**The question:** What triggers deregister() after close()?

---

## Part 4: Netty 3.x vs 4.x Event Model

### Evolution of Lifecycle Events

| Netty 3.x | Netty 4.x | Meaning |
|-----------|-----------|---------|
| `channelOpen` | `channelRegistered` | Added to EventLoop |
| `channelBound` | (merged) | Socket bound |
| `channelConnected` | `channelActive` | Connection ready |
| `channelDisconnected` | (merged) | Connection closed |
| `channelUnbound` | (merged) | Socket unbound |
| `channelClosed` | `channelUnregistered` | Removed from EventLoop |

**Reference:** [New and Noteworthy in 4.0](https://netty.io/wiki/new-and-noteworthy-in-4.0.html)

### What Changed

Netty 3.x had **6 separate events** for connection lifecycle.

Netty 4.x **simplified to 4 events** but added explicit registration state:
- `channelRegistered` / `channelUnregistered` control Selector membership
- This allows **dynamic registration** - channels can be deregistered and re-registered

From the migration docs:
> "They are new states introduced to support dynamic registration, deregistration, and re-registration of a Channel"

---

## Part 5: IdleStateHandler Integration

### Purpose

[IdleStateHandler](https://netty.io/4.1/api/io/netty/handler/timeout/IdleStateHandler.html) monitors channel activity and fires events when idle thresholds are reached.

**How it works:**
```
IdleStateHandler schedules timeout task
     │
     └── If no activity within threshold:
             └── Fire IdleStateEvent
                     └── Handler receives event
                             └── Handler calls ctx.close()
```

### The Integration Point

When `ctx.close()` is called:
1. Triggers `channelInactive()` in pipeline
2. **Should eventually trigger** `channelUnregistered()`
3. Channel removed from Selector

**The assumption:** Step 2 happens automatically through framework hooks.

---

## Part 6: The Legacy Glue Problem

### What "Legacy Glue" Likely Means

When migrating from Netty 3.x to 4.x, applications built on 3.x patterns need translation:

```
Netty 3.x Code Pattern
    │
    └── Expects: channelClosed event
    │
    └── Legacy Glue Layer translates to Netty 4.x
    │
    └── Should map to: channelInactive + channelUnregistered
```

### The Integration Failure Mode

**Hypothesis based on documentation:**

**With legacy glue enabled:**
```
ctx.close() called
    │
    └── Socket closes
    │
    └── channelInactive() fires
    │
    └── Legacy glue translates to 3.x-style cleanup
    │
    └── [MISSING] deregister() never called
    │
    └── Channel stays registered with Selector
```

**With legacy glue disabled:**
```
ctx.close() called
    │
    └── Socket closes
    │
    └── channelInactive() fires
    │
    └── Native Netty 4.x lifecycle hooks
    │
    └── deregister() automatically called
    │
    └── Channel removed from Selector
```

### Configuration Property

**Setting:** `com.fortra.netty.use_legacy_glue`

**Behavior change:**
- `true` - Uses compatibility layer that may not trigger deregister()
- `false` - Uses native Netty 4.x lifecycle with automatic deregister()

---

## Part 7: The Compound Effect

### FTP Passive Mode + Broken Deregister

Each SFTP session over SSH creates multiple channels:
- SSH control channel
- SFTP subsystem channels (multiple)

**When cleanup fails:**
```
Session #1
    ├── Control channel (stays registered)
    ├── Data channel 1 (stays registered)
    └── Data channel 2 (stays registered)

Session #2
    ├── Control channel (stays registered)
    └── Data channel 1 (stays registered)

[... sessions accumulate ...]

Selector polling loop:
    ├── Active session 1, channel 1  [useful work]
    ├── Zombie session 1, channel 1  [wasted CPU]
    ├── Zombie session 1, channel 2  [wasted CPU]
    ├── Zombie session 2, channel 1  [wasted CPU]
    └── [... continues for all registered channels ...]
```

### Traffic Spike Amplification

**Normal traffic:**
- N connections/day
- K% fail to deregister
- N × K zombie channels accumulate

**8x traffic spike:**
- 8N connections/day
- Same K% fail rate
- **8N × K zombie channels** accumulate

The selector overhead grows linearly with zombie count, but the selector must iterate ALL channels on EVERY select cycle.

---

## Part 8: What Changing the Setting Should Do

### Expected Behavior Change

**Configuration:**
```properties
com.fortra.netty.use_legacy_glue=false
```

### Predicted State Change

**Before:**
```
close() → channelInactive() → [END]
                                │
                           Selector still
                           polling dead channel
```

**After:**
```
close() → channelInactive() → deregister() → channelUnregistered()
                                                        │
                                                   Selector stops
                                                   polling channel
```

### Why This Matters

From Netty documentation:
> "When you deregister a Channel it basically removed itself from the servicing Thread which in the case of NIO also is the **Selector itself**."

**Deregister removes the channel from the Selector's registration set.**

Without deregister:
- Selector.select() returns keys for dead channels
- EventLoop processes them (no-op, no data)
- CPU cycles consumed per dead channel per select cycle

With deregister:
- Selector.select() doesn't return dead channels
- EventLoop only processes active channels
- CPU used only for productive work

---

## Part 9: Implementation Dependencies

### Component Interaction

```
Application Handler
    │
    └── Calls ctx.close()
            │
            ├──> Netty Pipeline
            │         │
            │         ├──> close() outbound event
            │         │         │
            │         │         └──> AbstractChannel.close()
            │         │                   │
            │         │                   └──> Socket.close()
            │         │                             │
            │         │                             └──> channelInactive() inbound event
            │         │
            │         └──> [CRITICAL INTEGRATION POINT]
            │                     │
            │                     ├─> Legacy Glue?
            │                     │       │
            │                     │       ├──> [YES] Stop here
            │                     │       │
            │                     │       └──> [NO] Continue ──> deregister() called
            │                     │                                     │
            │                     │                                     └──> Selector.register() removed
            │                     │
            │                     └──> channelUnregistered() inbound event
```

### The Integration Point

The legacy glue layer sits **between** `channelInactive()` and `deregister()`.

If it translates to Netty 3.x patterns:
- Stops processing after channelInactive
- Never calls deregister
- Channel stays registered

If disabled:
- Native Netty 4.x flow continues
- deregister called automatically
- Channel removed from Selector

---

## Part 10: Testing & Verification

### What to Monitor

**Session state metrics:**
```
Total channels registered with Selector
    vs
Channels with active I/O
    vs
Channels with bound sessions
```

**Selector behavior:**
```
Selector.select() call frequency
Selector.select() return count (# ready channels)
EventLoop CPU time per select cycle
```

**Lifecycle event counts:**
```
channelRegistered events
channelActive events
channelInactive events
channelUnregistered events  ← Should equal channelInactive after fix
```

### Expected Post-Fix Behavior

**Metric correlation:**
- `channelInactive` count ≈ `channelUnregistered` count
- Registered channel count ≈ Active session count
- Selector return count remains proportional to actual traffic

**If these diverge:**
- Channels not being deregistered
- Zombie accumulation continuing
- Configuration change not working as expected

---

## Summary: The Hypothesis

### Root Cause Theory

1. **FTP passive mode** creates multiple independent TCP connections per session
2. **Netty 3.x → 4.x migration** introduced explicit registration state
3. **Legacy compatibility layer** translates old lifecycle to new, but incompletely
4. **Missing deregister() call** leaves channels registered with Selector
5. **Selector polls dead channels** consuming CPU without productive work
6. **Traffic spikes** amplify zombie accumulation rate

### Configuration Change Theory

Setting `com.fortra.netty.use_legacy_glue=false`:
- Disables 3.x compatibility translation
- Enables native 4.x lifecycle hooks
- **Triggers automatic deregister()** after channel close
- Removes dead channels from Selector monitoring
- Eliminates wasted polling CPU

### What This Doesn't Fix

- Legitimate high traffic (still needs more CPU)
- Connections that are slow but not idle
- Application-level resource leaks outside Netty

### References

- [Netty Channel API](https://netty.io/4.0/api/io/netty/channel/Channel.html)
- [Netty 4.x User Guide](https://netty.io/wiki/user-guide-for-4.x.html)
- [IdleStateHandler](https://netty.io/4.1/api/io/netty/handler/timeout/IdleStateHandler.html)
- [New and Noteworthy in 4.0](https://netty.io/wiki/new-and-noteworthy-in-4.0.html)
- RFC 959 - File Transfer Protocol (FTP theory)

---

*This document presents a theoretical model based on documented Netty behavior and FTP protocol theory. Actual behavior depends on vendor implementation details not available in public documentation.*