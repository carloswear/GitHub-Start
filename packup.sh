#!/bin/sh

#install tools
#sudo apt-get -y install rsync dosfstools parted kpartx exfat-fuse

#mount USB device  （Model3B+'s USB device is auto mounted）
usbmount=/mnt
sudo mkdir -p $usbmount
sudo mount -o uid=osmc,gid=osmc /dev/sda $usbmount 
img=$usbmount/Backup/rpi-`date +%Y%m%d-%H%M`.img
#echo "$img"

echo ===================== part 1, create a new blank img ===============================
# create new file 
bootsz=`df -P | grep /boot | awk '{print $2}'`
rootsz=`df -P | grep /dev/mmcblk0p2 | awk '{print $3}'`
totalsz=`echo $bootsz $rootsz | awk '{print int(($1+$2)*1.5)}'`
echo "start generating img files , file size: ${totalsz} !"
sudo dd if=/dev/zero of=$img bs=1K count=$totalsz

# file partition 
bootstart=`sudo fdisk -l /dev/mmcblk0 | grep mmcblk0p1 | awk '{print $2}'`
bootend=`sudo fdisk -l /dev/mmcblk0 | grep mmcblk0p1 | awk '{print $3}'`
rootstart=`sudo fdisk -l /dev/mmcblk0 | grep mmcblk0p2 | awk '{print $2}'`
echo "boot & root size: ${bootstart}k >>> ${bootend}k, root: ${rootstart}k >>> end"
sudo parted $img --script -- mklabel msdos
sudo parted $img --script -- mkpart primary fat32 ${bootstart}s ${bootend}s
sudo parted $img --script -- mkpart primary ext4 ${rootstart}s -1
#format virtual disk 
loopdevice=`sudo losetup -f --show $img`
device=/dev/mapper/`sudo kpartx -va $loopdevice | sed -E 's/.*(loop[0-9])p.*/\1/g' | head -1`
sleep 5
sudo mkfs.vfat ${device}p1 -n boot
sudo mkfs.ext4 ${device}p2


echo ===================== part 2, fill the data to img =========================
# mount partitions
mountb=$usbmount/backup_boot/
mountr=$usbmount/backup_root/
sudo mkdir -p $mountb $mountr
# backup /boot 
sudo mount -t vfat ${device}p1 $mountb
sudo cp -rfp /boot/* $mountb
sync
echo "Boot partition done..."
# backup /root 
sudo mount -t ext4 ${device}p2 $mountr
#
if [ -f /etc/dphys-swapfile ]; then
        SWAPFILE=`cat /etc/dphys-swapfile | grep ^CONF_SWAPFILE | cut -f 2 -d=`
	if [ "$SWAPFILE" = "" ]; then
		SWAPFILE=/var/swap
	fi
	EXCLUDE_SWAPFILE="--exclude $SWAPFILE"
fi
#
sudo rsync --force -rltWDEgop --delete --stats --progress \
	$EXCLUDE_SWAPFILE \
	--exclude '.gvfs' \
	--exclude '/dev' \
        --exclude '/media' \
	--exclude '/mnt' \
	--exclude '/proc' \
        --exclude '/run' \
	--exclude '/sys' \
	--exclude '/tmp' \
        --exclude 'lost\+found' \
	--exclude '$usbmount' \
	// $mountr
# special dirs 
for i in dev media mnt proc run sys boot; do
	if [ ! -d $mountr/$i ]; then
		sudo mkdir $mountr/$i
	fi
done
if [ ! -d $mountr/tmp ]; then
	sudo mkdir $mountr/tmp
	sudo chmod a+w $mountr/tmp
fi
#
sudo rm -f $mountr/etc/udev/rules.d/70-persistent-net.rules

sync 
ls -lia $mountr/home/osmc/
echo "Root partition done..."


# replace PARTUUID
opartuuidb=`blkid -o export /dev/mmcblk0p1 | grep PARTUUID`
opartuuidr=`blkid -o export /dev/mmcblk0p2 | grep PARTUUID`
npartuuidb=`blkid -o export ${device}p1 | grep PARTUUID`
npartuuidr=`blkid -o export ${device}p2 | grep PARTUUID`
sudo sed -i "s/$opartuuidr/$npartuuidr/g" $mountb/cmdline.txt
sudo sed -i "s/$opartuuidb/$npartuuidb/g" $mountr/etc/fstab
sudo sed -i "s/$opartuuidr/$npartuuidr/g" $mountr/etc/fstab

#unmount，
sudo umount $mountb
sudo umount $mountr

# umount loop device
sudo kpartx -d $loopdevice
sudo losetup -d $loopdevice
#sudo umount $usbmount
sudo rm -rf $mountb $mountr
find /media/OSMC/Backup/ -mtime +180 -name "*.img" -exec rm -rf {} \;
find / -mtime +60 -name "nohup.out" -exec rm -rf {} \;
/usr/local/bin/bypy syncup /media/OSMC/Backup/ /backup true -v
#nohup /usr/local/bin/bypy syncup /media/OSMC/Backup/ /backup true -v &
echo "SUCCESS All done. You can pull up the backup device!"
echo "Your backup file is in $img"
