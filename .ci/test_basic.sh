#!/bin/bash -xe

# Simple configuration sanity checks
podman exec -it ovn-central ovn-nbctl show > nb_show
podman exec -it ovn-central ovn-sbctl show > sb_show

grep "(public)" nb_show
grep "(sw0)" nb_show
grep "(sw1)" nb_show
grep "(lr0)" nb_show


grep "Chassis ovn-gw-1" sb_show
grep "Chassis ovn-chassis-1" sb_show
grep "Chassis ovn-chassis-2" sb_show


# Some pings between the containers
podman exec -it ovn-chassis-1 ping -c 1 -w 1 170.168.0.2
podman exec -it ovn-chassis-1 ping -c 1 -w 1 170.168.0.3
podman exec -it ovn-chassis-1 ping -c 1 -w 1 170.168.0.5

podman exec -it ovn-chassis-2 ping -c 1 -w 1 170.168.0.2
podman exec -it ovn-chassis-2 ping -c 1 -w 1 170.168.0.3
podman exec -it ovn-chassis-2 ping -c 1 -w 1 170.168.0.4

podman exec -it ovn-gw-1 ping -c 1 -w 1 170.168.0.2
podman exec -it ovn-gw-1 ping -c 1 -w 1 170.168.0.4
podman exec -it ovn-gw-1 ping -c 1 -w 1 170.168.0.5
