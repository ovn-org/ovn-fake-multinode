#!/usr/bin/env bash

[ $EUID -eq 0 ] || { echo 'must be root' >&2; exit 1; }

set -o xtrace
set -o errexit

# Ref: https://linuxconfig.org/how-to-install-docker-in-rhel-8
dnf config-manager --add-repo=https://download.docker.com/linux/centos/docker-ce.repo
dnf install -y docker-ce

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
