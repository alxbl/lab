FROM ghcr.io/linuxserver/sonarr:4.0.20.3014-ls329
ENV ARR_APP_NAME=Sonarr
ENV ARR_DATA_DIR=/media/.config

# Customize config file
COPY sonarr/config.xml /config/config.xml
COPY custom-cont-init.d /custom-cont-init.d
# Override the service launch script to specify config path
COPY sonarr/svc-sonarr /etc/s6-overlay/s6-rc.d/svc-sonarr/run

RUN chown abc:users /media && chmod 0755 /media
