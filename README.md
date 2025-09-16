# sftp demo project

# Phase 1: Infrastructure Setup

## Structure
```
infrastructure/
├── terraform/
│   ├── main.tf              # GKE cluster definition
│   ├── storage.tf           # Filestore NFS + GCS bucket for archives
│   ├── variables.tf         # Configurable parameters
│   ├── outputs.tf           # Values needed by Helm (IPs, bucket names)
│   └── terraform.tfvars     # Actual values (gitignored)
└── scripts/
    └── deploy.sh            # Quick apply script
```

## Components Created

1. **GKE Cluster** - 2 node cluster, e2-medium instances
2. **Filestore** - 1TB NFS share for SFTP storage
3. **GCS Bucket** - Archive destination for old files

## Deployment
```bash
cd infrastructure/terraform
terraform init
terraform apply -auto-approve
terraform output  # Save these for Phase 2
```

## Outputs Required for Next Phase
- `filestore_ip` - NFS mount point for Helm PVC
- `archive_bucket` - GCS bucket name for archiver
- `cluster_endpoint` - GKE API endpoint
