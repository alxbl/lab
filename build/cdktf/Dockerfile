# cdktf.Dockerfile
#
# Dockerfile which creates a container that has all the dependencies required to 
# run cdktf and perform deployments.
#
# Image size is roughly 1.5GB, but it keeps host OS clean and makes it easy to
# provision the infrastructure from scratch.
#
# NOTE: To keep the size down, this image only supports the 
#       TypeScript language for projects. If you want to use 
#       python or golang, you will need to install the required
#       packages in the Docker image.
#
# NOTE: Because cdktf is running in a container, it currently 
#       cannot use Terraform docker providers.
#
# When using additional providers, it might be necessary to install dependencies
# in the docker image for them to properly run within the container.
#
FROM ubuntu:23.10

# Basic tools that are required for everything else.
RUN apt update && apt install -y curl unzip

# Install Azure CLI for `az login` next, because it doesn't clean up apt lists.
# https://learn.microsoft.com/en-us/cli/azure/install-azure-cli-linux?view=azure-cli-latest#option-1-install-with-one-command
RUN curl -sL https://aka.ms/InstallAzureCLIDeb | bash

# Install Node and other cdktf/terraform dependencies.
RUN apt install -y \
    nodejs \
    npm \
    ansible \
    golang \
    && rm -rf /var/lib/apt/lists/*
    
# Install Terraform
# https://developer.hashicorp.com/terraform/install
RUN curl https://releases.hashicorp.com/terraform/1.6.3/terraform_1.6.3_linux_amd64.zip \
      -o terraform.zip && \
    unzip terraform.zip -d /bin && \
    rm terraform.zip

# Install cdktf
# https://developer.hashicorp.com/terraform/tutorials/cdktf/cdktf-install#install-cdktf
RUN npm install -g cdktf-cli@0.20.3

WORKDIR /src
ENTRYPOINT ["cdktf"]
