# Container that periodically checks port forwarding status and updates qBitTorrent.
# Based on: https://hub.docker.com/r/blairy/requests
# Copied here because upstream is an indiviual.
FROM alpine:latest

# Install Python, Requests and tools
RUN \
  apk update --no-cache \
  && apk add \
    py3-pip \
    py3-beautifulsoup4 \
    py3-requests \
    bash \
    shadow \
    util-linux-misc \
  && apk upgrade 

# Specify Bash as our shell for the next RUN as ash does not 
# have required functionality.
SHELL ["/bin/bash", "-c"]

# Nuke existing users, create non-root user "python".
RUN \
  mkdir /home/python \
  && declare -a files=('/etc/shadow' '/etc/passwd' '/etc/group' 'sysctl.conf') \
  && for file in "${files[@]}"; do echo "" > $file; done \
  && rm -rf /root /etc/crontabs/root /sbin/apk \
  && useradd python -d /home/python -s /bin/bash \
  && chown -R python /home/python/ \
  && chmod -R 755 /home/python

# Change to non-root user "python"
USER python

# --- This part differs from base image.
# Copy pmpd script
COPY pmpd.py /home/python/pmpd.py
ENTRYPOINT ["/usr/bin/python", "/home/python/pmpd.py"]


