# Ref: https://wiki.archlinux.org/index.php/Dm-crypt/Encrypting_an_entire_system
# Ref: https://
# LUKS + LVM with signed linux kernel and secure boot
function read_pass {
    while : ; do
        echo -n "$1"
        read -s _P1 </dev/tty
        echo
        echo -n "Confirm: " </dev/tty
        read -s _P2
        echo
        if [[ -z "$_P1" || "$_P1" != "$_P2" ]]; then
            echo "Try again..."
        else
            PASSWD=$_P1
            unset _P1
            unset _P2
            return 0
        fi
    done
}

function pac_prepare_disk {
    local CROOT=cryptlvm
    local DISK=/dev/nvme0n1
    # Prepares the disk as an LVM on LUKS encrypted root partition.
    echo "[+] Partitioning ${DISK}"

    sed -e 's/\s*\([\+0-9a-zA-Z]*\).*/\1/'  <<EOF | gdisk ${DISK} >/dev/null
o     # ------ Create a clean GUID Partition Table ---
Y     # In case there is already a GPT
n     # ------ ${DISK}p1: ESP (500MB) ---
1     # Part:  1
      # Start: First aligned sector
+500M # End:   500MB later
ef00  # Type:  EFI (0xEF00)
n     # ------ ${DISK}p2: root (*) ---
2     # Part:  2
      # Start: Immediately after ESP
      # End:   100%
      # Type:  Linux (0x8300)
w     # ------ Write partition table
Y     # Confirm write
EOF

    mkfs.fat "${DISK}p1" # ESP

    echo "[+] Securely wiping disk..."
    cryptsetup open --type plain -d /dev/urandom "${DISK}p2" wipe
    dd if=/dev/zero of=/dev/mapper/wipe bs=1M status=progress
    cryptsetup close wipe

    echo "[+] Setting up full disk encryption"
    read_pass "[!] Encryption passphrase (do NOT forget): "
    cryptsetup luksFormat --type luks2 "${DISK}p2" <<EOF
YES
$PASSWD
$PASSWD
EOF
    cryptsetup open "${DISK}p2" $CROOT <<EOF
$PASSWD
EOF
    unset PASSWD # forget the passphrase.

    echo "[+] Creating volume group lvm0 on ${DISK}p2"
    pvcreate /dev/mapper/$CROOT
    vgcreate lvm0 /dev/mapper/$CROOT
    lvcreate -L 8G lvm0 -n swap
    lvcreate -l 100%FREE -n root

    mkswap /dev/lvm0/swap
    mkfs.ext4 /dev/lvm0/root

    echo "[+] Mounting..."
    mount /dev/lvm0/root /mnt
    mkdir /mnt/boot
    mount "${DISK}p1" /mnt/boot
    swapon /dev/lvm0/swap

    lsblk # Show the final disk layout
}

# Called when entering the arch-chroot
function pac_in_chroot {
    echo "[+] Install NetworkManager"
    pacman --noconfirm -S networkmanager sbsigntools

    echo "[+] Rebuild initcpio with encryption support"
    sed -i -e \ 's/^HOOKS=.*/HOOKS=(base udev autodetect modconf block filesystems keyboard keymap encrypt lvm2 fsck)/' /etc/mkinitcpio.conf
    mkinitcpio -p linux

    # If using additional partitions, you must add them to /etc/crypttab in
    # this hook.

}

function pac_do_bootloader {
    pacman --noconfirm -S efibootmgr
    eval "$(blkid "${DISK}p2" -o export)"
    echo "[+] Root partition UUID: $PARTUUID"
    # TODO: Clean up existing 'Arch Linux' entries
    # TODO: Set boot order? Goes to first by default.
    # efibootmgr | grep 'Arch Linux' | awk ... + for to destroy existing labels.

    # TODO Need root= when using cryptdevice? Will find out soon.
    efibootmgr \
        --disk /dev/sda \
        --part 1 \
        --create \
        --label 'Arch Linux' \
        --loader /vmlinuz-linux \
        --unicode "cryptdevice=UUID=$UUID:$CROOT root=PARTUUID=$PARTUUID rw initrd=\\initramfs-linux.img" --verbose
}


function pac_after_install {
    echo "[>] Don't forget to sign the EFISTUB and load keys into UEFI firmware!!"
}

