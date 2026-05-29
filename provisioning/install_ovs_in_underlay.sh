#!/usr/bin/env bash

[ $EUID -eq 0 ] || { echo 'must be root' >&2; exit 1; }

set -o xtrace
set -o errexit

dnf install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-10.noarch.rpm
curl -L http://trunk.rdoproject.org/centos10/delorean-deps.repo | sudo tee /etc/yum.repos.d/delorean-deps.repo

##dnf install -y libibverbs
##dnf install -y openvswitch openvswitch-ovn-central openvswitch-ovn-host
##for n in openvswitch ovn-northd ovn-controller ; do
##    systemctl enable --now $n
##    systemctl status $n
##done

dnf install -y libibverbs openvswitch
/usr/share/openvswitch/scripts/ovs-ctl --system-id=testovn start
ovs-vsctl show
