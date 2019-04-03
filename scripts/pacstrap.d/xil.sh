export DISK=/dev/vda
function pac_prepare_disk {
    # Prepares the disk as an LVM on LUKS encrypted root partition.
    echo "[+] Partitioning ${DISK}"

    sed -e 's/\s*\([\+0-9a-zA-Z]*\).*/\1/'  <<EOF | gdisk ${DISK} >/dev/null
o     # ------ Create a clean GUID Partition Table ---
Y     # In case there is already a GPT
n     # ------ ${DISK}1: ESP (500MB) ---
1     # Part:  1
      # Start: First aligned sector
+500M # End:   500MB later
ef00  # Type:  EFI (0xEF00)
n     # ------ ${DISK}2: root (*) ---
2     # Part:  2
      # Start: Immediately after ESP
      # End:   100%
      # Type:  Linux (0x8300)
w     # ------ Write partition table
Y     # Confirm write
EOF

    mkfs.fat "${DISK}1" # ESP
    mkfs.ext4 "${DISK}2" # root

    echo "[+] Mounting..."
    mount "${DISK}2" /mnt
    mkdir /mnt/boot
    mount "${DISK}1" /mnt/boot

    lsblk # Show the final disk layout
}

# Called when entering the arch-chroot
function pac_in_chroot {
    return
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
        --disk /dev/nvme0n1 \
        --part 1 \
        --create \
        --label 'Arch Linux' \
        --loader /vmlinuz-linux \
        --unicode "rw initrd=\\initramfs-linux.img root=${DISK}2" --verbose
}

function pac_after_install {
    return
}

