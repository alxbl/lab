FROM ghcr.io/linuxserver/readarr:develop
ENV ARR_APP_NAME=Readarr
ENV ARR_DATA_DIR=/media/.config

# Customize config file
COPY readarr/config.xml /config/config.xml
COPY custom-cont-init.d /custom-cont-init.d
# Override the service launch script to specify config path
COPY readarr/svc-readarr /etc/s6-overlay/s6-rc.d/svc-readarr/run

RUN chown abc:users /media && chmod 0755 /media
