#!/bin/sh

AZ_STORAGE_ACC=placeholder
AZ_CONTAINER=velero
AZURE_STORAGE_KEY=placeholder
AZURE_CLOUD_NAME=AzurePublicCloud
K8S_NAMESPACE='home'
kopia repository connect azure --storage-account $AZ_STORAGE_ACC \
    --container $AZ_CONTAINER \
    --storage-key $AZURE_STORAGE_KEY
    --prefix = "kopia/$K8S_NAMESPACE/"


kopia snapshot list --all


# Restore a vaultwarden backup
PVC_SNAPSHOT_ID='k...'
kopia restore $PVC_SNAPSHOT_ID


# create a junk TLS cert for VW and launch img
mkdir -p ../vm-tls
openssl req -newkey rsa:4096  -x509  -sha512  -days 365 -nodes -out ../vw-tls/domain.crt -keyout ../vw-tls/domain.key
sudo docker run --rm --name vw -v $(pwd):/data/ -v $(pwd)/../vw-tls:/opt -p 8080:80 -eROCKET_TLS='{certs="/opt/domain.crt",key="/opt/domain.key"}' -it vaultwarden/server
