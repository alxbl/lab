#!/bin/sh

# Helper script to download and unpack terraform standalone binaries.
TF_VERSION=1.7.2
TF_PLATFORM=linux
TF_ARCH=amd64

FILE="terraform_${TF_VERSION}_${TF_PLATFORM}_${TF_ARCH}.zip"
URL="https://releases.hashicorp.com/terraform/${TF_VERSION}/${FILE}"

echo "Downloading terraform $TF_VERSION to $(pwd)/bin..."
curl -o "$FILE" "$URL" && unzip "$FILE" -d bin/ && rm "$FILE"

