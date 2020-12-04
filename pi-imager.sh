#!/usr/bin/env bash
################################################################################
# pi-imager                                                                    #
# Raspberry Pi Image Loader Tool                                               #
# https://github.com/x82/bootstrappi                                           #
################################################################################

INTERACTIVE=True
CONFIG=bspi.config

# latest "Raspberry Pi OS Lite" image location
# LATEST_IMG='https://downloads.raspberrypi.org/raspios_lite_armhf/images/raspios_lite_armhf-2020-08-24/2020-08-20-raspios-buster-armhf-lite.zip'

# local cache during development
DEF_IMG_ZIP="http://192.168.1.190/2020-08-20-raspios-buster-armhf-lite.zip"

# other defaults if bspi.config does not exist yet
DEF_DEST_HOST="salt"
DEF_DEST_USER="pi"
DEF_DEST_PW="raspberry"
DEF_USE_CACHED="true"
DEF_GIT_IP="192.168.1.190"
DEF_GIT_USER="git"
DEF_GIT_PW="gitpassword"

set_config_var() {
  lua - "$1" "$2" "$3" <<EOF > "$3.bak"
local key=assert(arg[1])
local value=assert(arg[2])
local fn=assert(arg[3])
local file=assert(io.open(fn))
local made_change=false
for line in file:lines() do
  if line:match("^#?%s*"..key.."=.*$") then
    line=key.."="..value
    made_change=true
  end
  print(line)
end
if not made_change then
  print(key.."="..value)
end
EOF
mv "$3.bak" "$3"
}

clear_config_var() {
  lua - "$1" "$2" <<EOF > "$2.bak"
local key=assert(arg[1])
local fn=assert(arg[2])
local file=assert(io.open(fn))
for line in file:lines() do
  if line:match("^%s*"..key.."=.*$") then
    line="#"..line
  end
  print(line)
end
EOF
mv "$2.bak" "$2"
}

get_config_var() {
  lua - "$1" "$2" <<EOF
local key=assert(arg[1])
local fn=assert(arg[2])
local file=assert(io.open(fn))
local found=false
for line in file:lines() do
  local val = line:match("^%s*"..key.."=(.*)$")
  if (val ~= nil) then
    print(val)
    found=true
    break
  end
end
if not found then
   print(0)
end
EOF
}

# Configuration setting validation
validate_hostname() {
  regex='^[a-zA-Z0-9][-a-zA-Z0-9]{0,62}$'
  [[ "$1" =~ $regex ]]
}

validate_username() {
  regex='^[a-z_]([a-z0-9_-]{0,31}|[a-z0-9_-]{0,30}\$)$'
  [[ "$1" =~ $regex ]]
}


do_load_defaults() {
  # load config from file or defaults
  IMG_ZIP=$(get_config_var zipimgurl $CONFIG)
  if [ -z $IMG_ZIP ] || [ $IMG_ZIP = "0" ]; then
    IMG_ZIP=$DEF_IMG_ZIP
  fi
  set_config_var zipimgurl $IMG_ZIP $CONFIG

  DEST_HOST=$(get_config_var hostname $CONFIG)
  if [ -z $DEST_HOST ] || [ $DEST_HOST = "0" ]; then
    DEST_HOST=$DEF_DEST_HOST
  fi
  set_config_var hostname $DEST_HOST $CONFIG

  DEST_USER=$(get_config_var username $CONFIG)
  if [ -z $DEST_USER ] || [ $DEST_USER = "0" ]; then
    DEST_USER=$DEF_DEST_USER
  fi
  set_config_var username $DEST_USER $CONFIG

  DEST_PW=$(get_config_var password $CONFIG)
  if [ -z $DEST_PW ] || [ $DEST_PW = "0" ]; then
    DEST_PW=$DEF_DEST_PW
  fi
  set_config_var password $DEST_PW $CONFIG

  USE_CACHED=$(get_config_var usecached $CONFIG)
  if [ -z $USE_CACHED ] || [ $USE_CACHED = "0" ]; then
    USE_CACHED=$DEF_USE_CACHED
  fi
  set_config_var usecached $USE_CACHED $CONFIG

  GIT_IP=$(get_config_var gitip $CONFIG)
  if [ -z $GIT_IP ] || [ $GIT_IP = "0" ]; then
    GIT_IP=$DEF_GIT_IP
  fi
  set_config_var gitip $GIT_IP $CONFIG

  GIT_USER=$(get_config_var gituser $CONFIG)
  if [ -z $GIT_USER ] || [ $GIT_USER = "0" ]; then
    GIT_USER=$DEF_GIT_USER
  fi
  set_config_var gituser $GIT_USER $CONFIG

  GIT_PW=$(get_config_var gitpassword $CONFIG)
  if [ -z $GIT_PW ] || [ $GIT_PW = "0" ]; then
    GIT_PW=$DEF_GIT_PW
  fi
  set_config_var gitpassword $GIT_PW $CONFIG

  echo "DEBUG:"
  echo "IMG_ZIP = " $IMG_ZIP
  echo "DEST_HOST = " $DEST_HOST
  echo "DEST_USER = " $DEST_USER
  echo "DEST_PW = " $DEST_PW
  echo "USE_CACHED = " $USE_CACHED
  echo "GIT_IP = " $GIT_IP
  echo "GIT_USER = " $GIT_USER
  echo "GIT_PW = " $GIT_PW
  echo ""
}

# We're installing packages so we'll need root permissions.
if [ $(id -u) -ne 0 ]; then
  echo "Script must be run as root. Try 'sudo ./pi-imager.sh'"
  exit 1
fi

[ -e $CONFIG ] || touch $CONFIG

do_load_defaults

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
  wget "$url" -O /tmp/raspi_image.zip
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
    apt-get -y install git salt-master salt-minion python-pygit2 sshpass
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
  autologin)
    systemctl set-default multi-user.target
    ln -fs /lib/systemd/system/getty@.service /etc/systemd/system/getty.target.wants/getty@tty1.service
    cat > /etc/systemd/system/getty@tty1.service.d/autologin.conf << EOCF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin pi --noclear %I Linux
EOCF
    exit 0
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
    /opt/bspi/bin/bspi autologin

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
