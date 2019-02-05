#!/bin/bash

#            DO WHAT THE FUCK YOU WANT TO PUBLIC LICENSE
#                    Version 2, December 2004
#
# Copyright (C) 2019 Red Hat, Inc.
#
# Everyone is permitted to copy and distribute verbatim or modified
# copies of this license document, and changing it is allowed as long
# as the name is changed.
#
#            DO WHAT THE FUCK YOU WANT TO PUBLIC LICENSE
#   TERMS AND CONDITIONS FOR COPYING, DISTRIBUTION AND MODIFICATION
#
#  0. You just DO WHAT THE FUCK YOU WANT TO.

udevadm trigger
udevadm settle

# iterate over all interfaces and set them up
readarray -t interfaces < <(ip l | awk -F ":" '/^[0-9]+:/{dev=$2 ; if ( dev !~ /^ lo$/) {print $2}}')
for iface in "${interfaces[@]// /}"
do
    /sbin/ifup $iface
done

function write_ignition_file() {
    # check for the boot partition
    mkdir -p /mnt/boot_partition
    local BOOT_DEV=$(blkid -t "LABEL=boot" -o device "${DEST_DEV}"*)
    mount "${BOOT_DEV}" /mnt/boot_partition
    trap 'umount /mnt/boot_partition' RETURN

    FINAL_IGNITION=$(cat /tmp/config.ign)
    echo $FINAL_IGNITION > /mnt/boot_partition/config.ign
    rm /tmp/config.ign

    if  [ "$IGNITION_URL" != "skip" ];then
        sed -i "/^linux16/ s/$/ coreos.config.url=${IGNITION_URL//\//\\/}/" /mnt/boot_partition/grub2/grub.cfg
    fi
}

############################################################
#Get the image url to install
############################################################
let retry=0
while true
do
	IMAGE_URL=$(cat /tmp/image_url)
	curl -sIf $IMAGE_URL >/tmp/image_info 2>&1
	RETCODE=$?
	if [ $RETCODE -ne 0 ]
	then
		if [ $RETCODE -eq 22 -a $retry -lt 5 ]
		then
			# Network isn't up yet, sleep for a sec and retry
			sleep 1
			let retry=$retry+1
			continue
		fi
        echo "Image Lookup Error $RETCODE for \n $IMAGE_URL"
	else
		IMAGE_SIZE=$(cat /tmp/image_info | awk '/.*Content-Length.*/ {print $2}' | tr -d $'\r')
		TMPFS_MBSIZE=$(dc -e"$IMAGE_SIZE 1024 1024 * / 50 + p")
		echo "Image size is $IMAGE_SIZE" >> /tmp/debug
		echo "tmpfs sized to $TMPFS_MBSIZE MB" >> /tmp/debug
		break;
	fi
	rm -f /tmp/image_url
done

############################################################
#Get the ignition url to install
############################################################
echo "Getting ignition url" >> /tmp/debug
IGNITION_URL=$(cat /tmp/ignition_url)
rm -f /tmp/ignition_url

DEST_DEV=$(cat /tmp/selected_dev)
DEST_DEV=/dev/$DEST_DEV

#########################################################
#Create the tmpfs filesystem to store the image
#########################################################
echo "Mounting tmpfs" >> /tmp/debug
mkdir -p /mnt/dl
mount -t tmpfs -o size=${TMPFS_MBSIZE}m tmpfs /mnt/dl

#########################################################
#And Get the Image
#########################################################
echo "Downloading install image" >> /tmp/debug
curl -o /mnt/dl/imagefile.raw $IMAGE_URL

#########################################################
#Wipe any remaining disk labels
#########################################################
dd conv=nocreat count=1024 if=/dev/zero of="${DEST_DEV}" \
        seek=$(($(blockdev --getsz "${DEST_DEV}") - 1024)) status=none

#########################################################
#And Write the image to disk
#########################################################
echo "Writing disk image" >> /tmp/debug
dd if=/mnt/dl/imagefile.raw bs=1M oflag=direct of="${DEST_DEV}" status=none

for try in 0 1 2 4; do
        sleep "$try"  # Give the device a bit more time on each attempt.
        blockdev --rereadpt "${DEST_DEV}" && unset try && break
done
udevadm settle

#########################################################
# If one was provided, install the ignition config
#########################################################
write_ignition_file

if [ ! -f /tmp/skip_reboot ]
then
	sleep 5
	reboot --reboot --force
fi

