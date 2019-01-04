#!/bin/sh


chvt 2

############################################################
# Helper to write the ignition config
############################################################
function write_ignition() if [[ -f /tmp/ignition.cfg ]]; then
    # The OEM partition should be #6 but make no assumptions here!
    # Also don't mount by label directly in case other devices conflict.
    dialog --title 'CoreOS Installer' --infobox "Installing ignition config" 5 70
    local OEM_DEV=$(blkid -t "LABEL=OEM" -o device "${DEST_DEV}"*)

    mkdir -p /mnt/oemfs
    mount "${OEM_DEV}" /mnt/oemfs
    trap 'umount /mnt/oemfs' RETURN

    cp /tmp/ignition.cfg /mnt/oemfs/config.ign
    sleep 1
fi


chvt 2

############################################################
#Get the image url to install
############################################################
let retry=0
while true
do
	echo "Getting image URL $IMAGE_URL" >> /tmp/debug
	if [ ! -f /tmp/image_url ]
	then
		dialog --title 'CoreOS Installer' --inputbox "Enter the CoreOS Image URL
        to install" 5 75 "https://192.168.126.1/images/rhcos-qemu.raw" 2>/tmp/image_url
	fi

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
		dialog --title 'CoreOS Installer' --msgbox "Image Lookup Error $RETCODE for \n $IMAGE_URL" 10 70
	else
		IMAGE_SIZE=$(cat /tmp/image_info | awk '/.*Content-Length.*/ {print $2}' | tr -d $'\r')
		TMPFS_MBSIZE=$(dc -e"$IMAGE_SIZE 1024 1024 * / 50 + p")
		echo "Image size is $IMAGE_SIZE" >> /tmp/debug
		echo "tmpfs sized to $TMPFS_MBSIZE MB" >> /tmp/debug
		break;
	fi
	rm -f /tmp/image_url
done
dialog --clear

############################################################
#Get the ignition url to install
############################################################
while true
do
	echo "Getting ignition url" >> /tmp/debug
	if [ ! -f /tmp/ignition_url ]
	then
		echo "Prompting for ignition url" >> /tmp/debug
		dialog --title 'CoreOS Installer' --inputbox "Enter the CoreOS ignition config URL to install, or 'skip' for none" 5 75 "skip" 2>/tmp/ignition_url
	fi

	IGNITION_URL=$(cat /tmp/ignition_url)
	echo "IGNITION URL is $IGNITION_URL" >> /tmp/debug
	echo $IGNITION_URL | grep -q "^skip$"
	if [ $? -eq 0 ]
	then
		break;
	fi

	curl -sI $IGNITION_URL >/tmp/ignition.cfg 2>&1
	RETCODE=$?
	if [ $RETCODE -ne 0 ]
	then
		dialog --title 'CoreOS Installer' --msgbox "Image Lookup Error $RETCODE for \n $IGNITION_URL" 10 70
	else
		break;
	fi
	rm -f /tmp/ignition_url
done
dialog --clear

###########################################################
#Build the list of devices to install to
###########################################################
DEVLIST=""
lsblk -l -o NAME > /tmp/blk_devs
for i in `cat /tmp/blk_devs`
do
DEVLIST="$DEVLIST $i $i"
done

##########################################################
#Present the list to the user to select from
#########################################################
while true
do
	echo "Getting install device" >> /tmp/debug
	if [ ! -f /tmp/selected_dev ]
	then
		dialog --title 'CoreOS Installer' --menu "Select a Device to Install to" 45 45 35 $DEVLIST 2> /tmp/selected_dev
	fi

	DEST_DEV=$(cat /tmp/selected_dev)
	DEST_DEV=/dev/$DEST_DEV

	if [ ! -b $DEST_DEV ]
	then
		dialog --title 'CoreOS Installer' --msgbox "$DEST_DEV does not exist, reselect." 5 40
		rm -f /tmp/selected_dev
	else
		echo "Selected device is $DEST_DEV" >> /tmp/debug
		break;
	fi
done

dialog --clear

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
curl -s -o /mnt/dl/imagefile.raw $IMAGE_URL &

while true
do
	pidof curl
	if [ $? -ne 0 ]
	then
		break;
	fi
	if [ ! -f /mnt/dl/imagefile.raw ]
	then
		sleep 1
		continue
	fi
	PART_FILE_SIZE=$(ls -l /mnt/dl/imagefile.raw | awk '{print $5}') 2>/dev/null
	PCT=$(dc -e"2 k $PART_FILE_SIZE $IMAGE_SIZE / 100 * p" | sed -e"s/\..*$//" 2>/dev/null)
	echo $PCT
	sleep 1
done | dialog --title 'CoreOS Installer' --guage "Downloading Image" 10 70


#########################################################
#Wipe any remaining disk labels
#########################################################
dialog --title 'CoreOS Installer' --infobox "Wiping ${DEST_DEV}" 10 70
dd conv=nocreat count=1024 if=/dev/zero of="${DEST_DEV}" \
        seek=$(($(blockdev --getsz "${DEST_DEV}") - 1024)) status=none

#########################################################
#And Write the image to disk
#########################################################
echo "Writing disk image" >> /tmp/debug
# Note we add some to the image size so the dialog doesn't sit at 100% for a long time
(dd if=/mnt/dl/imagefile.raw bs=1M oflag=direct of="${DEST_DEV}" status=none) 2>&1 |\
 dialog --title 'CoreOS Installer' --guage "Writing image to disk" 10 70

for try in 0 1 2 4; do
        sleep "$try"  # Give the device a bit more time on each attempt.
        blockdev --rereadpt "${DEST_DEV}" && unset try && break
done
udevadm settle

#########################################################
# If one was provided, install the ignition config
#########################################################
write_ignition

if [ ! -f /tmp/skip_reboot ]
then
	dialog --title 'CoreOS Installer' --infobox "Install Complete.  Rebooting...." 10 70
	sleep 5
	reboot
fi

