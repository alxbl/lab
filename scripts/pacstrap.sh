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
if [ -z "$1" ]; then
    echo "Error: Hostname is required for pacstrap."
    echo "Usage: pacstrap.sh <hostname>"
    exit 1
fi

echo "Hostname: $1"

# Check if host specific file exists.
# Check if curl exists


