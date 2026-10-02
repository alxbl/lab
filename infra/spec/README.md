# Simplified Home Lab Architecture

It was fun learning k8s, but this is much easier to maintain as a full-time dad with 10 minutes per day.

TL;DR: rootless podman-compose with a script to generate and enable quadlets for persistent services (can be run as root anyway)

## Ingress

traefik is the ingress on its own network.

- NET_BIND_SERVICE to allow listening on port 80/443
- 80 -> 443 redirect
- ACME integration w/ Let's Encrypt and DNS01 challenges


## System Components

### Keycloak: Single Sign-On

### AdGuard-Home: Ad and Tracking Blocker

### Backup: Kopia-Powered Incremental Backups

### Vaultwarden: Password Management

## Monitoring Components

### Grafana: Dashboards

### Mimir: Metrics

### Fluentd: Logs

## Home Components

### Home-Assistant: Home Automation

### Immich: Photo Server

### Jellyfin: Media Server

### Smbd: File Server

### Acquisition: Arrrrrr!