#!/bin/bash

######
###### This function creates the patch file for initramfs in $1
######

create_patch_file () {

cat > $1 <<"PATCHFILE"
#!/usr/bin/sh
echo "Qubes initramfs script here: "

mkdir -p /proc /sys /dev
mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t devtmpfs devtmpfs /dev

if [ -w /sys/devices/system/xen_memory/xen_memory0/scrub_pages ]; then
    # re-enable xen-balloon pages scrubbing, after initial balloon down
    echo 1 > /sys/devices/system/xen_memory/xen_memory0/scrub_pages
fi

if [ -e /dev/mapper/dmroot ] ; then 
    echo "Qubes: FATAL error: /dev/mapper/dmroot already exists?!"
fi

/sbin/modprobe xenblk || /sbin/modprobe xen-blkfront || echo "Qubes: Cannot load Xen Block Frontend..."

die() {
    echo "$@" >&2
    exit 1
}

echo "Waiting for /dev/xvda* devices... LOL"
while ! [ -e /dev/xvda ]; do sleep 0.1; done

# prefer partition if exists
if [ -b /dev/xvda1 ]; then
    if [ -d /dev/disk/by-partlabel ]; then
        ROOT_DEV=$(readlink "/dev/disk/by-partlabel/Root\\x20filesystem")
        ROOT_DEV=${ROOT_DEV##*/}
    else
        ROOT_DEV=$(grep -l "PARTNAME=Root filesystem" /sys/block/xvda/xvda*/uevent |\
            grep -o "xvda[0-9]")
    fi
    if [ -z "$ROOT_DEV" ]; then
        # fallback to third partition
        ROOT_DEV=xvda3
    fi
else
    ROOT_DEV=xvda
fi

SWAP_SIZE=$(( 1024 * 1024 * 2 )) # sectors, 1GB

if [ `cat /sys/class/block/$ROOT_DEV/ro` = 0 ] ; then
    echo "Qubes: Setting up full RW storage for TemplateVM..."

    while ! [ -e /dev/xvdc ]; do sleep 0.1; done
    VOLATILE_SIZE=$(cat /sys/class/block/xvdc/size) # sectors
    ROOT_SIZE=$(cat /sys/class/block/$ROOT_DEV/size) # sectors
    if [ $VOLATILE_SIZE -lt $SWAP_SIZE ]; then
        die "volatile.img smaller than 1GB, cannot continue"
    fi
    /sbin/sfdisk -q --unit S /dev/xvdc >/dev/null <<EOF
xvdc1: type=82,start=2048,size=$SWAP_SIZE
xvdc2: type=83
EOF
    if [ $? -ne 0 ]; then
        echo "Qubes: failed to setup partitions on volatile device"
        exit 1
    fi
    while ! [ -e /dev/xvdc1 ]; do sleep 0.1; done
    /sbin/mkswap /dev/xvdc1
    while ! [ -e /dev/xvdc2 ]; do sleep 0.1; done

    ln -s ../$ROOT_DEV /dev/mapper/dmroot

    echo Qubes: done.
fi

if [ `cat /sys/class/block/$ROOT_DEV/ro` = 1 ] && [ `cat /sys/class/block/xvdb/ro` = 0 ] ; then

   echo "Qubes: Doing partial encrypted COW for AppVM..."

   while ! [ -e /dev/xvdc ]; do sleep 0.1; done
   VOLATILE_SIZE=$(cat /sys/class/block/xvdc/size)
   ROOT_SIZE=$(cat /sys/class/block/$ROOT_DEV/size)
   if [ $VOLATILE_SIZE -lt $SWAP_SIZE ]; then
       die "volatile smaller than swap cannot continue"
   fi

    /sbin/sfdisk -q --unit S /dev/xvdc >/dev/null <<EOF
xvdc1: type=82,start=2048,size=$SWAP_SIZE
xvdc3: type=83
EOF
    if [ $? -ne 0 ]; then
        die "Qubes: failed to setup partitions on volatile device"
    fi

    while ! [ -e /dev/xvdc1 ]; do sleep 0.1; done
    /sbin/mkswap /dev/xvdc1

    while ! [ -e /dev/xvdc3 ]; do sleep 0.1; done
    echo "Creating COW for root..."
    echo "0 $ROOT_SIZE snapshot /dev/$ROOT_DEV /dev/xvdc3 N 16" | /sbin/dmsetup create dmroot
    /sbin/dmsetup mknodes dmroot

    echo "Qubes: done."

fi

if [ `cat /sys/class/block/$ROOT_DEV/ro` = 1 ] && [ `cat /sys/class/block/xvdb/ro` = 1 ] ; then
    echo "Qubes: Doing full COW setup for DispVM..."

    while ! [ -e /dev/xvdc ]; do sleep 0.1; done
    while ! [ -e /dev/xvdb ]; do sleep 0.1; done
    VOLATILE_SIZE=$(cat /sys/class/block/xvdc/size) # sectors
    PRIVATE_SIZE=$(cat /sys/class/block/xvdb/size) # sectors
    ROOT_SIZE=$(cat /sys/class/block/$ROOT_DEV/size) # sectors
    if [ $VOLATILE_SIZE -lt $SWAP_SIZE ]; then
        die "volatile.img smaller than 1GB, cannot continue"
    fi

    # If xvdb is too large make snapshot occupy half of the partition

    if [ $PRIVATE_SIZE -gt $(($VOLATILE_SIZE / 2)) ]; then
	FINAL_SIZE=$(($VOLATILE_SIZE / 2))
    else
        FINAL_SIZE=$PRIVATE_SIZE
    fi

    /sbin/sfdisk -q --unit S /dev/xvdc >/dev/null <<EOF
xvdc1: type=82,start=2048,size=$SWAP_SIZE
xvdc2: type=83,start=$((2048 + $SWAP_SIZE)), size=$FINAL_SIZE
xvdc3: type=83
EOF
    if [ $? -ne 0 ]; then
        die "Qubes: failed to setup partitions on volatile device"
    fi
    while ! [ -e /dev/xvdc1 ]; do sleep 0.1; done
    echo "Creating partition for swap..."
    /sbin/mkswap /dev/xvdc1

    while ! [ -e /dev/xvdc2 ]; do sleep 0.1; done
    echo "Creating COW for home..."
    echo "0 $PRIVATE_SIZE snapshot /dev/xvdb /dev/xvdc2 N 16" | /sbin/dmsetup create dmhome
    /sbin/dmsetup mknodes dmhome

    while ! [ -e /dev/xvdc3 ]; do sleep 0.1; done
    echo "Creating encrypted COW for root..."
    echo "0 $ROOT_SIZE snapshot /dev/$ROOT_DEV /dev/xvdc3 N 16" | /sbin/dmsetup create dmroot
    /sbin/dmsetup mknodes dmroot

    echo "Qubes: done."
fi

mkdir -p /sysroot
mount /dev/mapper/dmroot /sysroot -o rw
NEWROOT=/sysroot

# Edit local fstab to reflect new devices

if [ `cat /sys/class/block/$ROOT_DEV/ro` = 1 ] && [ `cat /sys/class/block/xvdb/ro` = 1 ] ; then

    FSTAB=`cat $NEWROOT/etc/fstab`
    echo "${FSTAB/xvdb/mapper/dmhome}" > $NEWROOT/etc/fstab

fi

/sbin/modprobe ext4

kver="`uname -r`"
if ! [ -d "$NEWROOT/lib/modules/$kver/kernel" ]; then
    echo "Waiting for /dev/xvdd device..."
    while ! [ -e /dev/xvdd ]; do sleep 0.1; done

    mkdir -p /tmp/modules
    echo "Trying to mount /rw ... "

    mount -n -t ext3 /dev/xvdd /tmp/modules

    if /sbin/modprobe overlay; then
        # if overlayfs is supported, use that to provide fully writable /lib/modules
        if ! [ -d "$NEWROOT/lib/.modules_work" ]; then
            mkdir -p "$NEWROOT/lib/.modules_work"
        fi
        mount -t overlay none $NEWROOT/lib/modules -o lowerdir=/tmp/modules,upperdir=$NEWROOT/lib/modules,workdir=$NEWROOT/lib/.modules_work
    else
        # otherwise mount only `uname -r` subdirectory, to leave the rest of
        # /lib/modules writable
        if ! [ -d "$NEWROOT/lib/modules/$kver" ]; then
            mkdir -p "$NEWROOT/lib/modules/$kver"
        fi
        mount --bind "/tmp/modules/$kver" "$NEWROOT/lib/modules/$kver"
    fi

    rmdir /tmp/modules
fi

umount /dev /sys /proc
mount "$NEWROOT" -o remount,ro

exec /sbin/switch_root $NEWROOT /sbin/init
PATCHFILE

}

### Beginning of script proper
### Check that the usage is correct first

KERNEL_DIR=/var/lib/qubes/vm-kernels

if [ $# -lt 1 ]; then
   echo "Usage: $0 [name of kernel to patch]"
   exit -1
fi

if ! [ -d $KERNEL_DIR/$1 ]; then
   echo "No kernel with such a name found in /var/lib/qubes/vm-kernels" 
   exit -1
fi

PATCH_FILE=/tmp/init_patch

# Patched kernels are called "kernel~eph"
# The presence of another character ~ in the name of
# the kernel would be disastrous for this script

kernel=$1

echo "Patching initramfs..."

mkdir /tmp/$kernel.patch
cd /tmp/$kernel.patch
lsinitrd $KERNEL_DIR/$kernel/initramfs --unpack
create_patch_file /tmp/$kernel.patch/init
find . -print | cpio -ov -H newc > $KERNEL_DIR/$kernel/initramfs
cd ~
rm -rf /tmp/$kernel.patch

