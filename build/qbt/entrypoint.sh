#!/bin/sh
# Adapted from official Docker image (https://github.com/qbittorrent/docker-qbittorrent-nox)

if [ -z "$QBT_DOWNLOAD_DIR" ]; then
    QBT_DOWNLOAD_DIR="/downloads"
fi

if [ -z "$QBT_CONFIG_DIR"]; then
    QBT_CONFIG_DIR="/config"
else
fi

qbtConfigFile="$QBT_CONFIG_DIR/qBittorrent/config/qBittorrent.conf"

##
# Customize User/Group ids
##
if [ -n "$PUID" ]; then
    sed -i "s|^qbtUser:x:[0-9]*:|qbtUser:x:$PUID:|g" /etc/passwd
fi

if [ -n "$PGID" ]; then
    sed -i "s|^\(qbtUser:x:[0-9]*\):[0-9]*:|\1:$PGID:|g" /etc/passwd
    sed -i "s|^qbtUser:x:[0-9]*:|qbtUser:x:$PGID:|g" /etc/group
fi

if [ -n "$PAGID" ]; then
    _origIFS="$IFS"
    IFS=','
    for AGID in $PAGID; do
        AGID=$(echo "$AGID" | tr -d '[:space:]"')
        addgroup -g "$AGID" "qbtGroup-$AGID"
        addgroup qbtUser "qbtGroup-$AGID"
    done
    IFS="$_origIFS"
fi

##
# Default config
##
if [ -n "$QBT_CONFIG_SOURCE" ]; then # Copy config from source
    mkdir -p "$(dirname $qbtConfigFile)"
    cp "$QBT_CONFIG_SOURCE" "$qbtConfigFile"
elif [ ! -f "$qbtConfigFile" ]; then # Otherwise create a default config
    mkdir -p "$(dirname $qbtConfigFile)"
    cat << EOF > "$qbtConfigFile"
[BitTorrent]
Session\DefaultSavePath=$QBT_DOWNLOAD_DIR
Session\Port=6881
Session\TempPath=$QBT_DOWNLOAD_DIR/temp

[LegalNotice]
Accepted=true
EOF
fi

if [ -z "$QBT_WEBUI_PORT" ]; then
    QBT_WEBUI_PORT=8080
fi

##
# WebUI admin password
##
if [ -n "$QBT_WEBUI_PASSWORD_HASH"]; then
    sed -i "s#^WebUI\\\\Password_PBKDF2=.*\$#WebUI\\\\Password_PBKDF2=\"@ByteArray($QBT_WEBUI_PASSWORD_HASH)\"#g" "$qbtConfigFile"
fi

##
# Directory/File ownership
##
if [ -d "$QBT_DOWNLOAD_DIR" ]; then
    chown qbtUser:qbtUser "$QBT_DOWNLOAD_DIR"
fi
if [ -d "$QBT_CONFIG_DIR" ]; then
    chown qbtUser:qbtUser -R "$QBT_CONFIG_DIR"
fi

if [ -n "$UMASK" ]; then
    umask "$UMASK"
fi

exec \
    doas -u qbtUser \
        qbittorrent-nox \
            --profile="$QBT_CONFIG_DIR" \
            --webui-port="$QBT_WEBUI_PORT" \
            "$@"
