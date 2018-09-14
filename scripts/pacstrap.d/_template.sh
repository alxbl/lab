# This file specifies the hooks that are called during the pacstrap.sh
# execution.  It makes it possible to have different partitioning schemes and
# configuration for different machines based on their desired hostname.
# Make a copy of the file with the desired hostname and it will be used by
# pacstrap.sh

# Called when the disk needs to be partitioned and formatted.  After this
# function, the entire filesystem should be mounted to /mnt for pacstrap.
function pac_prepare_disk {
    echo "HOOK: pac_prepare_disk"
    # This is the place to format the disk, setup disk encryption
    # and mount the partitions.
}

# Called when entering the arch-chroot all commands executed here are ran in
# the chroot, and can be used to configure the system
function pac_in_chroot {
    echo "HOOK: pac_in_chroot"
}

# Called when the bootloader is ready to be installed. This is also called in
# the chroot
function pac_do_bootloader {
    echo "HOOK: pac_do_bootloader"
    # This is the place to configure the bootloader and install required
    # boot entries.
}

# Called after the install script has finished. Makes it possible to print
# additonal information.  or display messages to the user.
function pac_after_install {
    echo "HOOK: pac_after_install
}




