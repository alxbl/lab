FROM ghcr.io/linuxserver/radarr:latest
ENV ARR_APP_NAME=Radarr
ENV ARR_DATA_DIR=/media/.config

# Customize config file
COPY radarr/config.xml /config/config.xml
COPY custom-cont-init.d /custom-cont-init.d
# Override the service launch script to specify config path
COPY radarr/svc-radarr /etc/s6-overlay/s6-rc.d/svc-radarr/run

RUN chown abc:users /media && chmod 0755 /media
