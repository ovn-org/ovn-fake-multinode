#!/usr/bin/env bash

[ $EUID -eq 0 ] || { echo 'must be root' >&2; exit 1; }

set -o xtrace
set -o errexit

# Ref: https://linuxconfig.org/how-to-install-docker-in-rhel-8
dnf config-manager --add-repo=https://download.docker.com/linux/centos/docker-ce.repo

# We can get docker to work on Centos 8 in of these 2 ways
if false; then
    dnf install -y --nobest docker-ce
else
    dnf install -y docker-ce-3:18.09.1-3.el7
    dnf install -y https://download.docker.com/linux/centos/7/x86_64/stable/Packages/containerd.io-1.2.6-3.3.el7.x86_64.rpm
fi

[ -d /home/vagrant ] && usermod -a -G docker vagrant

# Enable IPv6 (https://github.com/moby/moby/issues/36954)
[ -e /etc/docker/daemon.json ] && { echo 'ERROR: docker/daemon.json already exists' >&2; exit 2; }
mkdir -pv /etc/docker && cat <<EOT >/etc/docker/daemon.json
{
  "ipv6": true,
  "fixed-cidr-v6": "2001:db8:1::/64"
}
EOT


systemctl disable firewalld ||:  ;  # yuck!
systemctl enable --now docker
