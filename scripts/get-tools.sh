#!/bin/zsh
# Helper script to download and unpack standalone tooling without polluting the host OS.

if [[ ! -v LAB_ROOT ]]; then
  echo "ERROR: Please source .env before running this script."
  exit 1
fi

BIN_PATH="$LAB_ROOT/scripts/bin"

PLATFORM=linux
K9S_PLATFORM=Linux
ARCH=amd64

TF_VERSION=1.7.2
HELM_VERSION=3.14.3
K9S_VERSION="0.32.4"



if [[ ! -a "$BIN_PATH/terraform" ]]; then
    TF_FILE="terraform_${TF_VERSION}_${PLATFORM}_${ARCH}.zip"
    TF_URL="https://releases.hashicorp.com/terraform/${TF_VERSION}/${TF_FILE}"
    echo "Downloading terraform $TF_VERSION to $BIN_PATH..."
    curl -o "$TF_FILE" "$TF_URL" && unzip "$TF_FILE" -d bin/ && rm "$TF_FILE"
else
    echo "Terraform already present. Using it..."
fi

if [[ ! -a "$BIN_PATH/helm" ]]; then

    echo "Downloading helm $HELM_VERSION to $BIN_PATH..."
    HELM_FILE="helm-v$HELM_VERSION-$PLATFORM-$ARCH.tar.gz"
    HELM_URL="https://get.helm.sh/$HELM_FILE"
    curl -o "$HELM_FILE" "$HELM_URL" && tar --strip-components 1 -C "$BIN_PATH" -xf "$HELM_FILE" "$PLATFORM-$ARCH/helm" && rm "$HELM_FILE"
else
    echo "helm already present. Using it..."
fi

if [[ ! -a "$BIN_PATH/k9s" ]]; then

    echo "Downloading k9s $K9S_VERSION to $BIN_PATH..."
    K9S_FILE="k9s_${K9S_PLATFORM}_$ARCH.tar.gz"
    K9S_URL="https://github.com/derailed/k9s/releases/download/v$K9S_VERSION/$K9S_FILE"
    curl -L -o "$K9S_FILE" "$K9S_URL" && tar -C "$BIN_PATH" -xf "$K9S_FILE" "k9s" && rm "$K9S_FILE"
else
    echo "k9s already present. Using it..."
fi

#   curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
