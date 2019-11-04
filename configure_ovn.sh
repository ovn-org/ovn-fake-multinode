#!/bin/bash

ovn_remote=$2
eth=$1

if [ "$eth" = "" ]; then
    eth=eth1
fi

ovn_remote=$2

if [ "$ovn_remote" = "" ]; then
    ovn_remote="tcp:172.17.0.2:6642"
fi

ip=`ip addr show $eth | grep inet | grep -v inet6 | awk '{print $2}' | cut -d'/' -f1`

ovs-vsctl set open . external_ids:ovn-encap-ip=$ip
ovs-vsctl set open . external-ids:ovn-encap-type=geneve
ovs-vsctl set open . external-ids:ovn-remote=$ovn_remote

ovs-vsctl --if-exists del-br br-ex
ovs-vsctl add-br br-ex
ovs-vsctl set open . external-ids:ovn-bridge-mappings=public:br-ex
