#!/usr/bin/env bash
################################################################################
# pi-imager                                                                    #
# Raspberry Pi Image Loader Tool                                               #
# https://github.com/x82/bootstrappi                                           #
################################################################################

# latest "Raspberry Pi OS Lite" image location
url=${2:-'https://downloads.raspberrypi.org/raspios_lite_armhf/images/raspios_lite_armhf-2020-08-24/2020-08-20-raspios-buster-armhf-lite.zip'}

# We're installing packages so we'll need root permissions.
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

if [ ! -e /tmp/raspi_image.zip ] || [ $1 -eq "-f" ]; then
  wget "$url" -O /tmp/raspi_image.zip
fi

if [ -r /tmp/raspi_image.zip ]; then
  mkdir -p /tmp/raspi
  unzip -d /tmp/raspi /tmp/raspi_image.zip
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
mkdir -p /mnt/opt/bspi/bin
cat <<EOF > /mnt/opt/bspi/bin/bspi
#!/usr/bin/env bash
################################################################################
# bspi                                                                         #
# BootstrapPi = Raspberry Pi Salt / GitFS deployment platform                  #
# https://github.com/x82/bootstrappi                                           #
################################################################################

export DEBIAN_FRONTEND=noninteractive
EXITCODE=0

if [ \$(id -u) -ne 0 ]; then
  echo "Script must be run as root. Try 'sudo ./pi-imager.sh'"
  exit 1
fi

ping_gw() {
  ping -q -w 1 -c 1 `ip r | grep default | cut -d ' ' -f 3` > /dev/null && return 0 || return 1
}

case "\$1" in
  installsalt)
    echo "salt" > /etc/hostname
    hostname salt
    ping_gw || sleep 30
    ping_gw || sleep 30
    apt-get update &&
    apt-get -y install salt-master salt-minion python-pygit2
    EXITCODE=\$?
    exit \$EXITCODE
    ;;
  saltmasterconfig)
    if [ -e /etc/salt/master ]; then
      cat >> /etc/salt/master << EOCF
fileserver_backend:
  - gitfs
  - roots
gitfs_remotes:
  - https://github.com/x82/pimaster-formula.git
EOCF
      systemctl restart salt-master
      EXITCODE=\$?
      exit \$EXITCODE
    else
      exit 1
    fi
    ;;
esac
EOF
chmod +x /mnt/opt/bspi/bin/bspi
echo "/opt/bspi/bin/bspi executable created on disk image.."
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
case "\$1" in
  start)
    if [[ \$(/opt/bspi/bin/bspi installsalt) ]]; then
      log_action_msg "Installed salt and pygit2.."
    else
      log_action_msg "Salt / PyGit2 install failed!"
      exit 1
    fi
    
    if [[ \$(/opt/bspi/bin/bspi saltmasterconfig) ]]; then
      log_action_msg "Configured GitFS on Salt and restarted master.."
    else
      log_action_msg "Salt configuration / restart failed!"
      exit 1
    fi

    rm /etc/init.d/bspi &&
    update-rc.d bspi remove
    log_action_msg "Removed bspi script.."

    log_end_msg \$?
    ;;
  *)
    echo "Usage: \$0 start" >&2
    exit 3
    ;;
esac
EOF
chmod +x /mnt/etc/init.d/bspi
ln -sr /mnt/etc/init.d/bspi /mnt/etc/rc3.d/S99bspi
echo "/etc/init.d/bspi created and linked on disk image.."
umount /mnt/
losetup -d ${LOOP}
echo "Image unmounted and loop device destroyed.."
dd if=$imgfile of=/dev/mmcblk0 bs=4M status=progress conv=fsync
rm -f /tmp/raspi/*.img
echo "Image copied.  Load SD card in Raspberry Pi to run!"
