# Demo VM to test

function pac_prepare_disk {
    echo "[+] HOOK: pac_prepare_disk"
    # This is destructive. Format the disk to GPT

    echo "[+] Partitioning /dev/sda"

    # TODO: There must be a better way to do this...
    sed -e 's/\s*\([\+0-9a-zA-Z]*\).*/\1/'  <<EOF | gdisk /dev/sda >/dev/null
o     # New GPT
Y     # In case there is already a GPT partition
n     # New partition
1
      # default start
+500M # 500mb
ef00  # EFI
n
2
      # Default start
      # Default end
      # Default type
w     # Write partition table
Y     # Confirm
EOF
    lsblk
    mkfs.fat /dev/sda1
    mkfs.ext4 /dev/sda2

    echo "[+] Mounting..."
    mount /dev/sda2 /mnt
    mkdir /mnt/boot
    mount /dev/sda1 /mnt/boot
}


# Called when entering the arch-chroot
function pac_in_chroot {
    echo "[+] HOOK: pac_in_chroot"
}

function pac_do_bootloader {
    echo "[+] HOOK: pac_do_bootloader"
    pacman --noconfirm -S efibootmgr
    PARTID="$(blkid /dev/sda2 -o value | tail -1)"
    echo "[+] Root partition UUID: /dev/sda2: $PARTID"
    efibootmgr \
        --disk /dev/sda \
        --part 1 \
        --create \
        --label 'Arch Linux' \
        --loader /vmlinuz-linux \
        --unicode "root=PARTUUID=$PARTID rw initrd=\\initramfs-linux.img" --verbose

}




