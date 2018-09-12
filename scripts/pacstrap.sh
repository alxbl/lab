#!/usr/bin/zsh
#
# pacstrap.sh
#
# From live USB to fully running system in one command.
#

##
#
##
echo "pacstrap.sh -"
if [ -z "$HOST" || "$HOST" == "archiso" ]; then
    echo "Error: Hostname is required for pacstrap."
    echo "Usage: HOST=<hostname> pacstrap.sh"
    exit 1
fi

echo "Hostname: $HOST"

# Check if host specific file exists.
# Check if curl exists


