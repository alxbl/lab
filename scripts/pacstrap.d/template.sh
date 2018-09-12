# This file specifies the hooks that are called during the
# pacstrap.sh execution.
#

# Called when the disk needs to be partitioned and formatted.
# After this function, the entire filesystem should be mounted to
# /mnt for pacstrap.
function pac_prepare_disk {
    echo "HOOK: pac_prepare_disk"
}

# Called when entering the arch-chroot
function pac_in_chroot {
    echo "HOOK: pac_in_chroot"
}

function pac_do_bootloader {
    echo "HOOK: pac_do_bootloader"
}




