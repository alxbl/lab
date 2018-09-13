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
read USER </dev/tty
echo
echo -n "Choose a password: "
read -s _P1 </dev/tty
echo
echo -n "Confirm: "
read -s _P2 </dev/tty
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
    echo -n "[+] Resolving host-specific hooks... "
    curl -sSf $SPEC > /hooks.sh
    if [ $? -ne 0 ]; then
        echo "\nError: Could not retrieve hooks settings. Is this a known host?"
        exit 127
    fi
    echo "ok"

else
    echo "[+] Getting hooks locally from $1"
    cp "$1" /hooks.sh
fi

# Read in the host specific hooks.
source /hooks.sh

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
echo '%wheel ALL=(ALL) ALL' >> /mnt/etc/sudoers

echo  "[+] Generating fstab"
genfstab -U /mnt >> /mnt/etc/fstab


# Hacky way to get the handlers inside the chroot
PAC="/mnt/hooks.sh"
cp /hooks.sh "$PAC"

# FIXME: Secure random?
ROOTPW="$(cat /proc/sys/kernel/random/uuid)"

# TODO: Make a temporary ramfs to avoid dumping credentials to disk during install
echo "[+] chroot to /mnt"
cat >/mnt/provision.sh <<EOF
source /hooks.sh
pac_in_chroot
echo "[+] Configuring locale to en_CA.UTF-8"
sed -i -e 's/#en_CA.UTF-8/en_CA.UTF-8/' /etc/locale.gen
locale-gen
echo 'LANG=en_CA.UTF-8' > /etc/locale.conf

echo "[+] Setting hostname to $HOST"
echo "$HOST" > /etc/hostname
echo "127.0.0.1        $HOST.localdomain $HOST" >> /etc/hosts

echo "[+] Set root password."
passwd root <<END
$ROOTPW
$ROOTPW
END

echo "[+] Creating user"
useradd $USER -m -G wheel
passwd $USER <<END
$PASSWD
$PASSWD
END

pac_do_bootloader
EOF

chmod +x /mnt/provision.sh
arch-chroot /mnt /provision.sh

unset ROOTPW
unset PASSWD
rm /mnt/{provision,hooks}.sh

# TODO: Can't run systemctl from chroot => ansible-pull is broken.
cat >"/mnt/home/$USER/.ansible-init"  <<EOF
echo "[+] pacstrap.sh: fresh install detected."
echo "[+] Pulling ansible repository."
ansible-pull -U https://github.com/alxbl/config -d /tmp/.ansible -i hosts playbook.yml
echo "[+] ==> Success. Cleaning up."
sed -i -e '/^.*# PACSTRAP$/d' .bashrc
rm ~/.ansible-init
EOF
echo 'source .ansible-init # PACSTRAP' >> "/mnt/home/$USER/.bashrc"

#       Maybe a transient service that runs once at boot?
#
echo "==> Done."
echo "NOTE: If you are paranoid, arch-chroot /mnt passwd root"
echo "and change the root password to something you control"
echo "It is now possible to login with $USER and sudo as usual."
echo "[!] ansible-pull will run automatically on your first logon."
echo
echo "Safe to reboot..."


