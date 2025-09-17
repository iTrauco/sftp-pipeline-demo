#!/bin/bash

# Load environment variables
if [ -f .env ]; then
  export $(cat .env | xargs)
fi

# Get terraform outputs
FILESTORE_IP=$(cd ../infrastructure/terraform && terraform output -raw filestore_ip)
BUCKET=$(cd ../infrastructure/terraform && terraform output -raw archive_bucket)

# Deploy with all values
helm upgrade --install sftp ../sftp-helm-chart \
  -f qa-values.yaml \
  --set storage.filestoreIP=$FILESTORE_IP \
  --set archiver.gcsBucket=$BUCKET \
  --set users[0].username=$SFTP_USER \
  --set users[0].password=$SFTP_PASS
