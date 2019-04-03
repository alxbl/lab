#!/usr/bin/zsh
#
# pacstrap.sh
#
# From live USB to fully running system in "one" command.  This script evals
# shell scripts from the internet (my git repository) Do not run it as is
# unless you know what you are doing and/or trust me.
#
# This script will load an extra file called $HOST.sh and source it. This extra
# file contains function hooks that will be called at different points during
# the system installation to customize the installation per system.
# For details, see pacstrap.d/_template.sh
################################################################################

# Ansible Repository for ansible-pull
REPO="https://github.com/alxbl/config"
# Base path for scripts
BASE="https://raw.githubusercontent.com/alxbl/config/master/scripts"

# Retrieve configuration
################################################################################
# Get hostname
while : ; do
    if [[ -z "$HOST" || "$HOST" == "archiso" ]]; then
        echo -n "Hostname: "
        read HOST
    fi
    break
done
SPEC="$BASE/pacstrap.d/$HOST.sh?$(date +%s)"

# Get main user and password
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

# Print summary of configuration
################################################################################
echo "-- Summary ----"
echo "Scripts:    $BASE"
echo "Hostname:   $HOST"
echo "Settings:   $BASE/pacstrap.d/$HOST.sh"
echo "Ansible:    $REPO"
echo "---------------"

# Retrieve host configuration
################################################################################
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

source /hooks.sh # Load hooks

################################################################################
# INSTALL SCRIPT
################################################################################
echo -n "[+] Checking for UEFI... "
if [ ! -d /sys/firmware/efi/efivars ]; then
    echo "error"
    echo "[E] This script only supports UEFI installs right now."
    exit 42
else
    echo "ok"
fi

echo "[+] Preparing disk(s)"
pac_prepare_disk # HOOK

echo "[+] Installing base system"
pacstrap /mnt base base-devel zsh git ansible vim sudo
echo "[+] Add wheel group to sudoers"
echo '%wheel ALL=(ALL) NOPASSWD: ALL' >> /mnt/etc/sudoers

echo  "[+] Generating fstab"
genfstab -U /mnt >> /mnt/etc/fstab

echo "[+] Mounting tmpfs for provisioning scripts"
mount -t tmpfs -o size=1M /mnt/mnt

# Copy provisioning scripts inside the chroot
################################################################################
cp /hooks.sh "/mnt/mnt/hooks.sh"

# This phase is the script that must run in the chroot
# provision.sh will briefly contain the raw password for $USER but it
# resides on a tmpfs so it will never touch disk and be wiped at reboot.
cat >"/mnt/mnt/provision.sh" <<EOF
source /mnt/hooks.sh
pac_in_chroot
echo "[+] Setting timezone to Americas/Montreal"
ln -sf /usr/share/zoneinfo/America/Montreal /etc/localtime
echo "[+] Configuring locale to en_CA.UTF-8"
sed -i -e 's/#en_CA.UTF-8/en_CA.UTF-8/' /etc/locale.gen
locale-gen
echo 'LANG=en_CA.UTF-8' > /etc/locale.conf

echo "[+] Setting hostname to $HOST"
echo "$HOST" > /etc/hostname
echo "127.0.0.1        $HOST.localdomain $HOST" >> /etc/hosts

echo "[+] Creating user: $USER"
useradd $USER -m -G wheel -s /bin/zsh
passwd $USER <<END
$PASSWD
$PASSWD
END

echo "[+] Add authorized_keys"
mkdir -p "/home/$USER/.ssh" && chmod 700 "/home/$USER/.ssh"
curl -sSf "$BASE/../files/common/authorized_keys" --output "/home/$USER/.ssh/authorized_keys" && chmod 600 "/home/$USER/.ssh/authorized_keys"

echo "[+] Disable root login"
passwd -l root

echo "[+] Configure boot loader"
pac_do_bootloader

echo "[+] Configure ansible to run on first login."
cat >"/home/$USER/.ansible-init"  <<END
echo "[+] pacstrap.sh: fresh install detected."
echo "[+] Waiting for network... (Ctrl+C to abort and retry on next login)"
while : ; do
    ping -c1 -W1 8.8.8.8
    if [ $? -eq 0 ]; then
        break
    fi
done

echo "[+] Pulling ansible repository."
ANSIBLE_USER="$USER" ansible-pull -U "$REPO" -d /tmp/ansible -i hosts playbook.yml
echo "[+] ==> Success. Cleaning up."
rm ~/.zlogin
rm ~/.ansible-init
END

chown $USER:$USER "/home/$USER/.ansible-init"
echo 'source .ansible-init # PACSTRAP' >> "/home/$USER/.zlogin"
EOF
unset PASSWD

echo "[+] chroot to /mnt to continue installation"
chmod +x /mnt/mnt/provision.sh
arch-chroot /mnt /mnt/provision.sh

# Clean up
################################################################################
rm /mnt/mnt/{provision,hooks}.sh # Technically not necessary.
umount /mnt/mnt # unmount tmpfs

echo "==> Done."
echo "NOTE: If you are paranoid, arch-chroot /mnt passwd root"
echo "and change the root password to something you control"
echo "It is now possible to login with $USER and sudo as usual."
echo "   - Root login has been disabled"
echo "   - ansible-pull will run on first logon with $USER"

pac_after_install

echo "It is now safe to reboot..."


