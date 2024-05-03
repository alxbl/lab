FROM ghcr.io/linuxserver/prowlarr:latest
ENV ARR_APP_NAME=Prowlarr
ENV ARR_DATA_DIR=/media/.config

# Customize config file
COPY prowlarr/config.xml /config/config.xml
COPY custom-cont-init.d /custom-cont-init.d
# Override the service launch script to specify config path
COPY prowlarr/svc-prowlarr /etc/s6-overlay/s6-rc.d/svc-prowlarr/run

RUN chown abc:users /media && chmod 0755 /media
