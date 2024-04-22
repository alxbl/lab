# Vaultwarden

This is a simple chart that deploys vaultwarden as follows:

- A persistent volume mount on `/data`
- Non-root user
- Read-only root file system
- Service exposed over HTTP (Recommended: HTTPS ingress)
- Allow Ingress on port `80`


> **WARNING**: If you are deploying this in your own cluster, you probably want TLS termination and deny rules for direct HTTP traffic. 