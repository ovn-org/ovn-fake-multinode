#!/bin/bash -xe

PODMAN_BIN=${1:-podman}

# Simple configuration sanity checks
$PODMAN_BIN exec -it ovn-central-az1-1 ovn-nbctl show > nb_show
$PODMAN_BIN exec -it ovn-central-az1-1 ovn-sbctl show > sb_show

grep "(public1)" nb_show
grep "(sw01)" nb_show
grep "(sw11)" nb_show
grep "(lr1)" nb_show


grep "Chassis ovn-gw-1" sb_show
grep "Chassis ovn-chassis-1" sb_show
grep "Chassis ovn-chassis-2" sb_show


# Some pings between the containers
$PODMAN_BIN exec -it ovn-chassis-1 ping -c 1 -w 1 170.168.0.2
$PODMAN_BIN exec -it ovn-chassis-1 ping -c 1 -w 1 170.168.0.3
$PODMAN_BIN exec -it ovn-chassis-1 ping -c 1 -w 1 170.168.0.5

$PODMAN_BIN exec -it ovn-chassis-2 ping -c 1 -w 1 170.168.0.2
$PODMAN_BIN exec -it ovn-chassis-2 ping -c 1 -w 1 170.168.0.3
$PODMAN_BIN exec -it ovn-chassis-2 ping -c 1 -w 1 170.168.0.4

$PODMAN_BIN exec -it ovn-gw-1 ping -c 1 -w 1 170.168.0.2
$PODMAN_BIN exec -it ovn-gw-1 ping -c 1 -w 1 170.168.0.4
$PODMAN_BIN exec -it ovn-gw-1 ping -c 1 -w 1 170.168.0.5


# Check expected routes from nested namespaces

$PODMAN_BIN exec -it ovn-chassis-1 ip netns

# sw01p1 : dual stack
$PODMAN_BIN exec -it ovn-chassis-1 \
    ip netns exec sw01p1 ip --color=never -4 route > sw01p1_route
$PODMAN_BIN exec -it ovn-chassis-1 \
    ip netns exec sw01p1 ip --color=never -6 route >> sw01p1_route
cat sw01p1_route
grep "11.0.0.0/24 dev sw01p1" sw01p1_route
grep "default via 11.0.0.1 dev sw01p1" sw01p1_route
grep "1001::/64 dev sw01p1" sw01p1_route
grep "default via 1001::a dev sw01p1" sw01p1_route

echo 'happy happy, joy joy'
