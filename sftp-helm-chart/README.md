# SFTP Demo System

## What This Is
Helm-generated k8s manifests for an SFTP server with GCS archival.

## Resource Tree

```markdown
sftp-test/
├── configmap (sftp-test-scripts)
│   ├── upload.py                    # paramiko sftp upload to /upload/test.txt
│   ├── mock.py                      # generates json files every 1800s
│   │   ├── file_types: ['trigger', 'scheduler', 'user']
│   │   └── naming: {type}_{timestamp}_{random}.json
│   └── archive.py                   # moves old files to gcs
│       ├── trigger: 5 days
│       ├── scheduler: 14 days
│       └── user: 30 days
│
├── storage/
│   ├── pv (sftp-test-pv)
│   │   ├── capacity: 10Gi
│   │   ├── accessModes: ReadWriteMany
│   │   ├── nfs.server: <FILESTORE_IP>
│   │   └── nfs.path: /share1
│   │
│   └── pvc (sftp-test-pvc)
│       ├── accessModes: ReadWriteMany
│       ├── storage: 10Gi
│       └── volumeName: sftp-test-pv
│
├── service (sftp-test-sftp-service)
│   ├── type: LoadBalancer
│   ├── port: 22 → targetPort: 22
│   └── selector: app=sftp
│
├── deployment (sftp-test-sftp)
│   ├── replicas: 1
│   ├── selector: app=sftp
│   ├── container: atmoz/sftp:alpine
│   ├── args: ["REDACTED_USER:REDACTED_PASS:"]    # user:pass:uid format
│   └── volumeMounts: pvc → /home/REDACTED_USER/upload
│
└── cronjob (sftp-test-archiver)
    ├── schedule: "0 6 * * *"            # 6am daily
    ├── container: google/cloud-sdk:alpine
    ├── command: pip install paramiko google-cloud-storage && python /scripts/archive.py
    └── env:
        ├── SFTP_HOST: sftp-test-sftp-service
        ├── SFTP_USER: REDACTED_USER
        ├── SFTP_PASS: REDACTED_PASS
        ├── GCS_BUCKET: <GCS_BUCKET_NAME>
        ├── TRIGGER_DAYS: 5
        ├── SCHEDULER_DAYS: 14
        └── USER_DAYS: 30
```

## Helm Command Used
```bash
helm template sftp-test . \
  --set storage.filestoreIP="<FILESTORE_IP>" \
  --set archiver.gcsBucket="<GCS_BUCKET_NAME>" \
  --set 'users[0].username=REDACTED_USER' \
  --set 'users[0].password=REDACTED_PASS'
```

## What Each Script Does

**upload.py**: Uses paramiko to connect to SFTP_HOST:22 and uploads `/tmp/test.txt` to `/upload/test.txt`.

**mock.py**: Infinite loop that creates random JSON files in `/upload/` with metadata including type, created timestamp, and demo content. Sleeps 1800 seconds between runs.

**archive.py**: Connects to SFTP, lists `/upload/`, parses filenames for type and age, uploads to GCS bucket under `archive/{type}/` if older than threshold, then deletes from SFTP.

## Connection Points
- SFTP container exposes port 22 through LoadBalancer service.
- All containers mount the same NFS volume at different paths.
- Cronjob uses internal service name `sftp-test-sftp-service` to connect.
- Files flow: client → SFTP → NFS → cronjob → GCS.