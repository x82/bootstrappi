#!/usr/bin/env bash
################################################################################
# bootstrappi                                                                  #
# Raspberry Pi Bootstrap Tool for kicking off dynamic salt deployments         #
# https://github.com/x82/bootstrappi                                           #
################################################################################

# We're installing packages so we'll need root permissions.
if [ $(id -u) -ne 0 ]; then
  printf "Script must be run as root. Try 'sudo bspi.sh'\n"
  exit 1
fi

apt-get update && 
apt-get -y install salt-minion salt-master python-pygit2

if [ -e /etc/salt/master ]; then
  cat >> /etc/salt/master << EOF
fileserver_backend:
  - gitfs
  - roots
gitfs_remotes:
  - https://github.com/x82/pimaster-formula.git
EOF
  systemctl restart salt-master
else
  # oh noes!
  printf "The salt-master package does not appear to be installed correctly.\n"
  printf "Review the above installation process for the fault that occurred.\n"
fi

