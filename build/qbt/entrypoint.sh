#!/bin/sh
# Adapted from official Docker image (https://github.com/qbittorrent/docker-qbittorrent-nox)

if [ -z "$QBT_DOWNLOAD_DIR" ]; then
    QBT_DOWNLOAD_DIR="/downloads"
fi

if [ -z "$QBT_CONFIG_DIR" ]; then
    QBT_CONFIG_DIR="/config"
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
if [ -n "$QBT_WEBUI_PASSWORD" ]; then
    # Option 1: from plaintext secret
    # https://github.com/qbittorrent/qBittorrent/discussions/15454
    hash=$(python - "$QBT_WEBUI_PASSWORD" <<EOF
import hashlib
import base64
import uuid

password = "$QBT_WEBUI_PASSWORD"
salt = uuid.uuid4()
salt_bytes = salt.bytes

password = str.encode(password)
hashed_password = hashlib.pbkdf2_hmac('sha512', password, salt_bytes, 100000, dklen=64)
b64_salt = base64.b64encode(salt_bytes).decode("utf-8")
b64_password = base64.b64encode(hashed_password).decode("utf-8")
password_string = "{salt}:{password}".format(salt=b64_salt,password=b64_password)
print(password_string)
EOF
    )
    sed -i "s#^WebUI\\\\Password_PBKDF2=.*\$#WebUI\\\\Password_PBKDF2=\"@ByteArray($hash)\"#g" "$qbtConfigFile"

elif [ -n "$QBT_WEBUI_PASSWORD_HASH"]; then
    # Option 2: from password hash
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
