# Base Image: linuxserver.io
FROM ghcr.io/linuxserver/sonarr:4.0.3
ENV APP=Sonarr

# Customize config file
COPY sonarr/config.xml /config/config.xml
COPY custom-cont-init.d /custom-cont-init.d
# Override the service launch script to specify config path
COPY sonarr/svc-sonarr-override /etc/s6-overlay/s6-rc.d/svc-sonarr/run

RUN chown abc:users /media && chmod 0755 /media
