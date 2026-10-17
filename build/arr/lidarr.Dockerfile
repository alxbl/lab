FROM ghcr.io/linuxserver/lidarr:3.1.0.4875-ls43
ENV ARR_APP_NAME=Lidarr
ENV ARR_DATA_DIR=/media/.config

# Customize config file
COPY lidarr/config.xml /config/config.xml
COPY custom-cont-init.d /custom-cont-init.d
# Override the service launch script to specify config path
COPY lidarr/svc-lidarr /etc/s6-overlay/s6-rc.d/svc-lidarr/run

RUN chown abc:users /media && chmod 0755 /media
