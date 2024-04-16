#!/bin/bash
tmux new -s traffic \; \
  split-window -v   \; \
  split-window -v   \; \
  select-pane -t 1  \; \
  split-window -v   \; \
  select-pane -t 1  \; \
  split-window -h   \; \
  select-pane -t 3  \; \
  split-window -h   \; \
  select-pane -t 5  \; \
  split-window -h   \; \
  select-pane -t 7  \; \
  split-window -h   \; \
  select-pane -t 1  \; \
  send-keys 'podman exec -it ovn-chassis-1 ip netns exec sw01p3 nping -c 100000000 --icmp 11.0.0.3 11.0.0.6 21.0.0.1 21.0.0.3 8.8.8.8 172.16.0.110' C-m \; \
  select-pane -t 2  \; \
  send-keys 'podman exec -it ovn-chassis-1 ip netns exec sw01p3 nping -c 100000000 --udp 11.0.0.3 11.0.0.6 21.0.0.1 21.0.0.3 172.16.0.110' C-m \; \
  select-pane -t 3  \; \
  send-keys 'podman exec -it ovn-chassis-1 ip netns exec sw01p3 nping -c 100000000 --arp 11.0.0.3 11.0.0.6' C-m \; \
  select-pane -t 4  \; \
  send-keys 'podman exec -it ovn-chassis-1 ip netns exec sw01p3 nping -c 100000000 --tcp 11.0.0.3 11.0.0.6 21.0.0.1 21.0.0.3 172.16.0.110' C-m \; \
  select-pane -t 5  \; \
  send-keys 'podman exec -it ovn-chassis-1 ip netns exec sw01p1 ping6 2001::3' C-m \; \
  select-pane -t 6  \; \
  send-keys 'podman exec -it ovn-chassis-1 ip netns exec sw01p1 ping6 -t 1 2001::3' C-m \; \
  select-pane -t 7  \; \
  send-keys 'podman exec -it ovn-chassis-1 ip netns exec sw01p3 ping 21.0.0.3 -t 1' C-m \; \
  select-pane -t 8  \; \
  send-keys 'podman exec -it ovn-chassis-1 ip netns exec sw01p1 bash -c "export TOOLBOX_HOME=/vagrant/bench-uperf_git/toolbox; export RS_CS_LABEL=1-1; export PATH=/vagrant/uperf_git/src:${PATH}; cp -rv /vagrant/bench-uperf_git/xml-files/ /tmp/; /vagrant/bench-uperf_git/uperf-client --test-type=rr --wsize=64 --rsize=1024 --duration=3600 --protocol=tcp --nthreads=1024 --remotehost=11.0.0.6"' C-m \;
