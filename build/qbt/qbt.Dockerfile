FROM qbittorrentofficial/qbittorrent-nox:latest

COPY entrypoint.sh /entrypoint.sh
RUN chmod 0755 /entrypoint.sh