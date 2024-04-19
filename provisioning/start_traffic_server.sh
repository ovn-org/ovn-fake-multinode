#!/bin/bash
UPERF=/vagrant/uperf_git/src/uperf

tmux new -d -s uperf_server \; \
  send-keys "podman exec -it ovn-chassis-2 ip netns exec sw01p4 $UPERF -s -P 30002 -v" C-m \;
