#!/usr/bin/env bash
################################################################################
# bootstrappi                                                                  #
# Raspberry Pi Bootstrap Tool for kicking off dynamic salt deployments         #
# https://github.com/x82/bootstrappi                                           #
################################################################################

# Thanks to raspi-config https://github.com/RPi-Distro/raspi-config
# for much of their whiptail and pi-specific configuration code.

INTERACTIVE=True

USER=${SUDO_USER:-$(who -m | awk '{ print $1 }')}

# Using whiptail as it looks pretty simple and seems to work well.
calc_wt_size() {
  # NOTE: it's tempting to redirect stderr to /dev/null, so supress error 
  # output from tput. However in this case, tput detects neither stdout or 
  # stderr is a tty and so only gives default 80, 24 values
  WT_HEIGHT=18
  WT_WIDTH=$(tput cols)

  if [ -z "$WT_WIDTH" ] || [ "$WT_WIDTH" -lt 60 ]; then
    WT_WIDTH=80
  fi
  if [ "$WT_WIDTH" -gt 178 ]; then
    WT_WIDTH=120
  fi
  WT_MENU_HEIGHT=$(($WT_HEIGHT-7))
}

# check on whether we have successfully ran a dhcp client - possibly on our
# second boot script.  This will help determine whether we are running in
# client mode or deployment mode - maybe prompt too?

# maybe an initial menu, with pw change, non-interactive, interactive
# (later?), and exit.  perhaps add a note that hardware options and other
# niceties can be updated in raspi-config.

# first prompt for a password change, in case it's a fresh install
do_change_pass() {
  whiptail --msgbox "You will now be asked to enter a new password for the $USER user" 20 60 1
  passwd $USER &&
  whiptail --msgbox "Password changed successfully" 20 60 1
}

# change this to a prompt for interactive mode at the end.
do_about() {
  whiptail --msgbox "\
This tool provides is designed to turn an out-of-the-box Raspberry Pi (OS) into 
a dynamic staging platform for a salt deployment.  It is designed to be 
operated from a github gitfs configuration to ensure as the deployment can be
as customised as possible with the least possible amount of hard-coding in the 
toolchain.\
" 20 70 1
}

# set up autologin
# set up an init.d to resume after the first reboot.. where was this?
# check if possible and expand drive - we'll need some space.

# configure keyboard for US english - the default UK layout is annoying.
do_configure_keyboard() {
  printf "Reloading keymap. This may take a short while\n"
  if [ "$INTERACTIVE" = True ]; then
    dpkg-reconfigure keyboard-configuration
  else
    local KEYMAP="$1"
    sed -i /etc/default/keyboard -e "s/^XKBLAYOUT.*/XKBLAYOUT=\"$KEYMAP\"/"
    dpkg-reconfigure -f noninteractive keyboard-configuration
  fi
  invoke-rc.d keyboard-setup start
  setsid sh -c 'exec setupcon -k --force <> /dev/tty1 >&0 2>&1'
  udevadm trigger --subsystem-match=input --action=change
  return 0
}

# change timezone to UTC
do_change_timezone() {
  if [ "$INTERACTIVE" = True ]; then
    dpkg-reconfigure tzdata
  else
    local TIMEZONE="$1"
    if [ ! -f "/usr/share/zoneinfo/$TIMEZONE" ]; then
      return 1;
    fi
    rm /etc/localtime
    echo "$TIMEZONE" > /etc/timezone
    dpkg-reconfigure -f noninteractive tzdata
  fi
}

# check if hostname is raspberrypi, and if so, change to bootstrappi
get_hostname() {
    cat /etc/hostname | tr -d " \t\n\r"
}

do_hostname() {
  if [ "$INTERACTIVE" = True ]; then
    whiptail --msgbox "\
Please note: RFCs mandate that a hostname's labels \
may contain only the ASCII letters 'a' through 'z' (case-insensitive), 
the digits '0' through '9', and the hyphen.
Hostname labels cannot begin or end with a hyphen. 
No other symbols, punctuation characters, or blank spaces are permitted.\
" 20 70 1
  fi
  CURRENT_HOSTNAME=`cat /etc/hostname | tr -d " \t\n\r"`
  if [ "$INTERACTIVE" = True ]; then
    NEW_HOSTNAME=$(whiptail --inputbox "Please enter a hostname" 20 60 "$CURRENT_HOSTNAME" 3>&1 1>&2 2>&3)
  else
    NEW_HOSTNAME=$1
    true
  fi
  if [ $? -eq 0 ]; then
    echo $NEW_HOSTNAME > /etc/hostname
    sed -i "s/127.0.1.1.*$CURRENT_HOSTNAME/127.0.1.1\t$NEW_HOSTNAME/g" /etc/hosts
    ASK_TO_REBOOT=1
  fi
}

# minimise the memory split so we have as much RAM available as possible.
do_memory_split() { # Memory Split
  if [ -e /boot/start_cd.elf ]; then
    # New-style memory split setting
    ## get current memory split from /boot/config.txt
    arm=$(vcgencmd get_mem arm | cut -d '=' -f 2 | cut -d 'M' -f 1)
    gpu=$(vcgencmd get_mem gpu | cut -d '=' -f 2 | cut -d 'M' -f 1)
    tot=$(($arm+$gpu))
    if [ $tot -gt 512 ]; then
      CUR_GPU_MEM=$(get_config_var gpu_mem_1024 $CONFIG)
    elif [ $tot -gt 256 ]; then
      CUR_GPU_MEM=$(get_config_var gpu_mem_512 $CONFIG)
    else
      CUR_GPU_MEM=$(get_config_var gpu_mem_256 $CONFIG)
    fi
    if [ -z "$CUR_GPU_MEM" ] || [ $CUR_GPU_MEM = "0" ]; then
      CUR_GPU_MEM=$(get_config_var gpu_mem $CONFIG)
    fi
    [ -z "$CUR_GPU_MEM" ] || [ $CUR_GPU_MEM = "0" ] && CUR_GPU_MEM=64
    ## ask users what gpu_mem they want
    if [ "$INTERACTIVE" = True ]; then
      NEW_GPU_MEM=$(whiptail --inputbox "How much memory (MB) should the GPU have?  e.g. 16/32/64/128/256" \
        20 70 -- "$CUR_GPU_MEM" 3>&1 1>&2 2>&3)
    else
      NEW_GPU_MEM=$1
      true
    fi
    if [ $? -eq 0 ]; then
      if [ $(get_config_var gpu_mem_1024 $CONFIG) != "0" ] || [ $(get_config_var gpu_mem_512 $CONFIG) != "0" ] || [ $(get_config_var gpu_mem_256 $CONFIG) != "0" ]; then
        if [ "$INTERACTIVE" = True ]; then
          whiptail --msgbox "Device-specific memory settings were found. These have been cleared." 20 60 2
        fi
        clear_config_var gpu_mem_1024 $CONFIG
        clear_config_var gpu_mem_512 $CONFIG
        clear_config_var gpu_mem_256 $CONFIG
      fi
      set_config_var gpu_mem "$NEW_GPU_MEM" $CONFIG
      ASK_TO_REBOOT=1
    fi
  else # Old firmware so do start.elf renaming
    get_current_memory_split
    MEMSPLIT=$(whiptail --menu "Set memory split.\n$MEMSPLIT_DESCRIPTION" 20 60 10 \
      "240" "240MiB for ARM, 16MiB for VideoCore" \
      "224" "224MiB for ARM, 32MiB for VideoCore" \
      "192" "192MiB for ARM, 64MiB for VideoCore" \
      "128" "128MiB for ARM, 128MiB for VideoCore" \
      3>&1 1>&2 2>&3)
    if [ $? -eq 0 ]; then
      set_memory_split ${MEMSPLIT}
      ASK_TO_REBOOT=1
    fi
  fi
}

get_current_memory_split() {
  AVAILABLE_SPLITS="128 192 224 240"
  MEMSPLIT_DESCRIPTION=""
  for SPLIT in $AVAILABLE_SPLITS;do
    if [ -e /boot/arm${SPLIT}_start.elf ] && cmp /boot/arm${SPLIT}_start.elf /boot/start.elf >/dev/null 2>&1;then
      CURRENT_MEMSPLIT=$SPLIT
      MEMSPLIT_DESCRIPTION="Current: ${CURRENT_MEMSPLIT}MiB for ARM, $((256 - $CURRENT_MEMSPLIT))MiB for VideoCore"
      break
    fi
  done
}

set_memory_split() {
  cp -a /boot/arm${1}_start.elf /boot/start.elf
  sync
}

# shouldn't need to run sshd

# autologin will be useful for an automation tool we are building
get_autologin() {
  if [ $(get_boot_cli) -eq 0 ]; then
    # booting to CLI
    # stretch or buster - is there an autologin conf file?
    if [ -e /etc/systemd/system/getty@tty1.service.d/autologin.conf ] ; then
      echo 0
    else
      # stretch or earlier - check the getty service symlink for autologin
      if [ $(deb_ver) -le 9 ] && grep -q autologin /etc/systemd/system/getty.target.wants/getty@tty1.service ; then
        echo 0
      else
        echo 1
      fi
    fi
  else
    # booting to desktop - check the autologin for lightdm
    if grep -q "^autologin-user=" /etc/lightdm/lightdm.conf ; then
      echo 0
    else
      echo 1
    fi
  fi
}

do_boot_behaviour() {
  if [ "$INTERACTIVE" = True ]; then
    BOOTOPT=$(whiptail --title "Raspberry Pi Software Configuration Tool (raspi-config)" --menu "Boot Options" $WT_HEIGHT $WT_WIDTH $WT_MENU_HEIGHT \
      "B1 Console" "Text console, requiring user to login" \
      "B2 Console Autologin" "Text console, automatically logged in as '$USER' user" \
      "B3 Desktop" "Desktop GUI, requiring user to login" \
      "B4 Desktop Autologin" "Desktop GUI, automatically logged in as '$USER' user" \
      3>&1 1>&2 2>&3)
  else
    BOOTOPT=$1
    true
  fi
  if [ $? -eq 0 ]; then
    case "$BOOTOPT" in
      B1*)
        systemctl set-default multi-user.target
        ln -fs /lib/systemd/system/getty@.service /etc/systemd/system/getty.target.wants/getty@tty1.service
        rm /etc/systemd/system/getty@tty1.service.d/autologin.conf
        ;;
      B2*)
        systemctl set-default multi-user.target
        ln -fs /lib/systemd/system/getty@.service /etc/systemd/system/getty.target.wants/getty@tty1.service
        cat > /etc/systemd/system/getty@tty1.service.d/autologin.conf << EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin $USER --noclear %I \$TERM
EOF
        ;;
      B3*)
        if [ -e /etc/init.d/lightdm ]; then
          systemctl set-default graphical.target
          ln -fs /lib/systemd/system/getty@.service /etc/systemd/system/getty.target.wants/getty@tty1.service
          rm /etc/systemd/system/getty@tty1.service.d/autologin.conf
          sed /etc/lightdm/lightdm.conf -i -e "s/^autologin-user=.*/#autologin-user=/"
          disable_raspi_config_at_boot
        else
          whiptail --msgbox "Do 'sudo apt-get install lightdm' to allow configuration of boot to desktop" 20 60 2
          return 1
        fi
        ;;
      B4*)
        if [ -e /etc/init.d/lightdm ]; then
          systemctl set-default graphical.target
          ln -fs /lib/systemd/system/getty@.service /etc/systemd/system/getty.target.wants/getty@tty1.service
          cat > /etc/systemd/system/getty@tty1.service.d/autologin.conf << EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin $USER --noclear %I \$TERM
EOF
          sed /etc/lightdm/lightdm.conf -i -e "s/^\(#\|\)autologin-user=.*/autologin-user=$USER/"
          disable_raspi_config_at_boot
        else
          whiptail --msgbox "Do 'sudo apt-get install lightdm' to allow configuration of boot to desktop" 20 60 2
          return 1
        fi
        ;;
      *)
        whiptail --msgbox "Programmer error, unrecognised boot option" 20 60 2
        return 1
        ;;
    esac
    ASK_TO_REBOOT=1
  fi
}

# *** Note - once we have a near-complete installation, we can deploy an init.d script
# ***        to test network, do the gitfs updates, and run high state as required.

disable_raspi_config_at_boot() {
  if [ -e /etc/profile.d/raspi-config.sh ]; then
    rm -f /etc/profile.d/raspi-config.sh
    if [ -e /etc/systemd/system/getty@tty1.service.d/raspi-config-override.conf ]; then
      rm /etc/systemd/system/getty@tty1.service.d/raspi-config-override.conf
    fi
    telinit q
  fi
}

# if we want to get fancy later we can make and install a splash screen.

do_update() {
  apt-get update &&
  apt-get install raspi-config &&
  printf "Sleeping 5 seconds before reloading raspi-config\n" &&
  sleep 5 &&
  exec raspi-config
}

do_finish() {
  disable_raspi_config_at_boot
  if [ $ASK_TO_REBOOT -eq 1 ]; then
    whiptail --yesno "Would you like to reboot now?" 20 60 2
    if [ $? -eq 0 ]; then # yes
      sync
      reboot
    fi
  fi
  exit 0
}

# make a non-interactive mode to be able to "just go" and get deployed.
nonint() {
  "$@"
}

#
# Command line options for non-interactive use
#
for i in $*
do
  case $i in
  --nonint)
    INTERACTIVE=False
    printf "Non-interactive mode selected.\n"
    "$@"
    exit 0
    ;;
  *)
    # unknown option
    ;;
  esac
done

# Everything else needs to be run as root
if [ $(id -u) -ne 0 ]; then
  printf "Script must be run as root. Try 'sudo bspi.sh'\n"
  exit 1
fi

#
# Interactive use loop
#
if [ "$INTERACTIVE" = True ]; then
  calc_wt_size
  while [ "$USER" = "root" ] || [ -z "$USER" ]; do
    if ! USER=$(whiptail --inputbox "raspi-config could not determine the default user.\\n\\nWhat user should these settings apply to?" 20 60 pi 3>&1 1>&2 2>&3); then
      return 0
    fi
  done
  while true; do
    FUN=$(whiptail --title "Raspberry Pi Software Configuration Tool (raspi-config)" --backtitle "$(cat /proc/device-tree/model)" --menu "Setup Options" $WT_HEIGHT $WT_WIDTH $WT_MENU_HEIGHT --cancel-button Finish --ok-button Select \
      "1 System Options" "Configure system settings" \
      "2 Display Options" "Configure display settings" \
      "3 Interface Options" "Configure connections to peripherals" \
      "4 Performance Options" "Configure performance settings" \
      "5 Localisation Options" "Configure language and regional settings" \
      "6 Advanced Options" "Configure advanced settings" \
      "8 Update" "Update this tool to the latest version" \
      "9 About raspi-config" "Information about this configuration tool" \
      3>&1 1>&2 2>&3)
    fi
    RET=$?
    if [ $RET -eq 1 ]; then
      do_finish
    elif [ $RET -eq 0 ]; then
      case "$FUN" in
        1\ *) do_system_menu ;;
        2\ *) do_display_menu ;;
        3\ *) do_interface_menu ;;
        4\ *) do_performance_menu ;;
        5\ *) do_internationalisation_menu ;;
        6\ *) do_advanced_menu ;;
        8\ *) do_update ;;
        9\ *) do_about ;;
        *) whiptail --msgbox "Programmer error: unrecognized option" 20 60 1 ;;
      esac || whiptail --msgbox "There was an error running option $FUN" 20 60 1
    else
      exit 1
    fi
  done
fi
