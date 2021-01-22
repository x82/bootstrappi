#!/usr/bin/env bash
################################################################################
# pi-imager                                                                    #
# Raspberry Pi Image Loader Tool                                               #
# https://github.com/x82/bootstrappi                                           #
################################################################################

# latest "Raspberry Pi OS Lite" image location
# LATEST_IMG='https://downloads.raspberrypi.org/raspios_lite_armhf/images/raspios_lite_armhf-2020-08-24/2020-08-20-raspios-buster-armhf-lite.zip'

# local cache during development
INFRA_IP="192.168.1.190"
OS_IMG_URL="http://$INFRA_IP/2020-08-20-raspios-buster-armhf-lite.zip"

# other defaults if bspi.config does not exist yet
DEF_GIT_IP="$INFRA_IP"

# We're playing with file systems so we'll need root permissions.
if [ $(id -u) -ne 0 ]; then
  echo "Script must be run as root. Try 'sudo ./pi-imager.sh'"
  exit 1
fi

if [ $(lsblk -p | grep /dev/mmcblk0 | wc -l) -ne 0 ]; then
  printf "SD card detected at /dev/mmcblk0.\nBe warned, continuing will erase the "
  printf "contents of this card - press Ctrl-C to abort now!\n"
  read -p "Press [Enter] to continue ..."
else
  printf "No SD card detected at /dev/mmcblk0\n *** Note: if your SD cards show up on "
  printf "/dev/sdX, I'm not going to wipe your hard drive - you're on your own!\n"
  exit 1
fi 

if [ ! -e /tmp/raspi_image.zip ] || [ "$1" = "-f" ]; then
  wget "$OS_IMG_URL" -O /tmp/raspi_image.zip
fi

if [ -r /tmp/raspi_image.zip ]; then
  mkdir -p /tmp/raspi
  unzip -o -d /tmp/raspi /tmp/raspi_image.zip
  #rm -f /tmp/raspi_image.zip
else
  echo "The image download failed!  Please verify URL and network connectivity."
  exit 1
fi

files=(/tmp/raspi/*.img)
imgfile="${files}"
INFO="$(fdisk -lu "${imgfile}")"
START="$(grep Linux <<< "${INFO}" | awk '{print $2}')"
SIZE="$(grep Linux <<< "${INFO}" | awk '{print $4}')"
LOOP="$(losetup -f --show -o $((${START} * 512)) --sizelimit $((${SIZE} * 512)) "${imgfile}")"
mount "${LOOP}" /mnt/  
echo "Image $imgfile mounted on /mnt/.."
# now set up an init.d script
cat <<EOF > /mnt/etc/init.d/bspi
#!/bin/bash
### BEGIN INIT INFO
# Provides:          bspi
# Required-Start: networking
# Required-Stop:
# Default-Start: 3
# Default-Stop:
# Short-Description: Perform installation to deploy git-configured salt master
# Description:
### END INIT INFO
. /lib/lsb/init-functions

ping_gw() {
  ping -q -w 1 -c 1 `ip r | grep default | cut -d ' ' -f 3` > /dev/null && return 0 || return 1
}

case "\$1" in
  start)
    ping_gw || sleep 30
    ping_gw || sleep 30
    wget -O - http://$INFRA_IP/bspi.sh | bash
    ;;
  *)
    echo "Usage: \$0 start" >&2
    exit 3
    ;;
esac 
exit 0
EOF
chmod +x /mnt/etc/init.d/bspi
ln -sr /mnt/etc/init.d/bspi /mnt/etc/rc3.d/S99bspi
echo "/etc/init.d/bspi created and linked on disk image.."
mkdir /mnt/home/pi/.ssh
ssh-keygen -C "git@$INFRA_IP" -f /mnt/home/pi/.ssh/id_rsa -N ""
echo "SSH keys generated.  Log in to infra server to copy new key:"
ssh-copy-id -i /mnt/home/pi/.ssh/id_rsa.pub -o LogLevel=ERROR -o StrictHostKeyChecking=no git@$INFRA_IP
umount /mnt/
losetup -d ${LOOP}
echo "Image unmounted and loop device destroyed.."
dd if=$imgfile of=/dev/mmcblk0 bs=4M status=progress conv=fsync
rm -f /tmp/raspi/*.img
echo "Image copied.  Load SD card in Raspberry Pi to run!"
