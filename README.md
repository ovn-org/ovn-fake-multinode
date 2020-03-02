# ovn-fake-multinode

Using this repo, you can leverage nested namespaces to deploy
an OVN cluster where outer namespaces represent a compute node -- aka
OVN chassis. Inside each of these emulated chassis, we are then able
to create inner namespaces to emulate something comparable to ports of
a VM in a compute node.

For more details, take a look at this talk
from the [2019 OVScon](https://www.openvswitch.org/support/ovscon2019/):
[Deploying multi chassis OVN using docker in docker by Numan Siddique, Red Hat](https://www.openvswitch.org/support/ovscon2019/#7.3L):
[**Slides**](https://www.openvswitch.org/support/ovscon2019/day2/1319-siddique.pdf)
[**Video**](https://youtu.be/Pdd_pOMzQQM?t=97)

## Steps

Step 1: Build the container images

By default, Docker is used (we can switch to Podman later):
```
sudo OVN_SRC_PATH=<path_t_ovn_src_folder> OVS_SRC_PATH=<path_to_ovs_src_folder> ./ovn_cluster.sh build
```

This will create 2 docker images

- **ovn/cinc**: base image that gives us the nesting capability
- **ovn/ovn-multi-node**: built on top of cinc where ovs+ovn is compiled and installed

Step 2: Start openvswitch in your host

In order to interconnect the containers that emulate the chassis, we need an underlay network. This step is what provides that.
```
sudo /usr/share/openvswitch/scripts/ovs-ctl --system-id=testovn start
```

Step 3: Start the ovn-fake-multinode
```
sudo ./ovn_cluster.sh start
```

Step 4: Stop the ovn-fake-multinode and tweak cluster as needed
```
sudo ./ovn_cluster.sh stop

# look for start-container and configure-ovn functions in
vi ./ovn_cluster.sh

# Go back to step 3 and have fun!
```

### Getting into underlay

A port called *ovnfake-ext* is created in the fake underlay
network as part of *ovn_cluster.sh start*. You can use that
as an easy way of getting inside the cluster (via NAT in OVN).
Look for *ip netns add ovnfake-ext* in *ovn_cluster.sh*.
An example for doing that is shown here:
```
sudo ip netns exec ovnfake-ext bash
ip a
ip route
ping -i 1 -c 1 -w 1 172.16.0.110 >/dev/null && \
   echo 'happy happy, joy joy' || echo sad panda
exit
```

## Vagrant based VM

To deploy a VM that automatically performs the steps above as part of
it's provisioning, consider using Vagrantfile located in this repo.

```
git clone https://github.com/ovn-org/ovn-fake-multinode.git && \
cd ovn-fake-multinode && vagrant up && vagrant ssh
```
