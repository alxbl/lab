#!/usr/bin/zsh
#
# pacstrap.sh
#
# From live USB to fully running system in "one" command.  This script evals
# shell scripts from the internet (my git repository) Do not run it as is
# unless you know what you are doing and trust me.
#
BASE="https://raw.githubusercontent.com/alxbl/config/master/scripts"

echo "[+] pacstrap.sh"
if [[ -z "$HOST" || "$HOST" == "archiso" ]]; then
    echo "Error: Hostname is required for pacstrap."
    echo "Usage: HOST=<hostname> pacstrap.sh"
    exit 1
fi

# TODO: Cache busting?
SPEC="$BASE/pacstrap.d/$HOST.sh"
echo "Base URL: $BASE"
echo "Hostname: $HOST"
echo "Specific: $SPEC"
echo "---------------"

echo -n "Main user: "
read USER
echo
echo -n "Choose a password: "
read -s _P1
echo
echo -n "Confirm: "
read -s _P2
echo

if [[ -z "$USER" ]]; then
    echo "Type a valid username!"
    exit 4
fi
if [[ "$_P1" != "$_P2" ]]; then
    echo "Passwords do not match!"
    exit 3
fi

PASSWD="$_P1"
unset _P1
unset _P2

if [ -z "$1" ]; then
    echo -n "[+] Sourcing host-specific settings... "
    C=$(curl -s $SPEC)
    if [ $? -ne 0 ]; then
        echo "\nError: Could not retrieve host-specific settings. Is this a known host?"
        exit 127
    fi
    echo "ok"

else
    echo "[+] Sourcing locally"
    C=$(<"$1")
fi

# Shield your eyes now: This puts the functions in the script's scope.
# TODO: Could drop to disk instead since it needs to be moved to /mnt anyway
eval "$C"

echo -n "[+] Checking for UEFI... "
if [ ! -d /sys/firmware/efi/efivars ]; then
    echo "error"
    echo "This script only supports UEFI installs right now."
    exit 42
else
    echo "ok"
fi

echo "[+] Preparing disk(s)"
pac_prepare_disk

echo "[+] Installing base packages"
pacstrap /mnt base base-devel zsh git ansible vim sudo
echo '%wheel ALL=(ALL) ALL' >> /etc/sudoers

echo  "[+] Generating fstab"
genfstab -U /mnt >> /mnt/etc/fstab


# Hacky way to get the handlers inside the chroot
PAC="/mnt/pac_handler.sh"
echo "$C" >> "$PAC"

# FIXME: Secure random?
ROOTPW="$(cat /proc/sys/kernel/random/uuid)"

echo "[+] chroot to /mnt"
cat <<EOF | arch-chroot /mnt
source /pac_handler.sh
pac_in_chroot
echo "[+] Configuring locale to en_CA.UTF-8"
sed -i -e 's/#en_CA.UTF-8/en_CA.UTF-8/' /etc/locale.gen
locale-gen
echo 'LANG=en_CA.UTF-8' > /etc/locale.conf

echo "[+] Setting hostname to $HOST"
echo "$HOST" > /etc/hostname
echo "127.0.0.1        $HOST.localdomain $HOST" >> /etc/hosts

echo "[+] Restrict Root
passwd root <<END
$ROOTPW
$ROOTPW
END

echo "[+] Creating user"
useradd alex -m -G wheel
passwd alex <<END
$PASSWD
$PASSWD
END

pac_do_bootloader

exit
EOF

unset ROOTPW
unset PASSWD
rm /mnt/pac_handler.sh # Clean up the bootstrap script

# TODO: Can't run systemctl from chroot => ansible-pull is broken.
#       Maybe a transient service that runs once at boot?
#
echo "Done."
echo "If you are paranoid, arch-chroot /mnt passwd root"
echo "and change the root password to something you control"
echo "It is now possible to login with $USER and sudo as usual."
echo "Safe to reboot..."



