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

By default, podman is used (users can control the container runtime through
the `RUNC_CMD` environment variable):
```
sudo OVN_SRC_PATH=<path_to_ovn_src_folder> OVS_SRC_PATH=<path_to_ovs_src_folder> ./ovn_cluster.sh build
```

This will create 2 container images

- **ovn/cinc**: base image that gives us the nesting capability
- **ovn/ovn-multi-node**: built on top of cinc where ovs+ovn is compiled and installed

By default, these container images are built on top of `fedora:latest`. This behavior can be controlled
by two environment variables:

- `OS_IMAGE`: URL from which the base OCI image is pulled (default: `quay.io/fedora/fedora:latest`)
- `OS_BASE`: Which OS is used for the base OCI image. Supported values are `fedora` and `ubuntu`
  (default: `fedora`)

When compiling OVN with `./ovn_cluster.sh build`, you can specify the exact compiler flags to use by exporting an `OVN_CFLAGS` environment variable.

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

### Testing underlay

If CREATE_FAKE_VMS=no was not set during build, running the following command
will check the health of the underlay.
```
sudo ./.ci/test_basic.sh
```
You should see "happy happy, joy joy" printed for a successful run

### Pre-provisioning NB and/or SB databases.
It's sometime useful to be able to start up a cluster with pre-existing
OVN NB and/or SB databases. For example, when debugging an issue from
a real production cluster. In order to achieve that the `OVN_NBDB_SRC
and `OVN_SBDB_SRC` variables can be used:
```
OVN_NBDB_SRC=some-nb.db OVN_SBDB_SRC=some-sb.db ./ovn_cluster.sh start
```

## Vagrant based VM

To deploy a VM that automatically performs the steps above as part of
it's provisioning, consider using Vagrantfile located in this repo.

```
git clone https://github.com/ovn-org/ovn-fake-multinode.git && \
cd ovn-fake-multinode && vagrant up && vagrant ssh
```

### Vagrant based development

If you would like to use the _Vagrant_ based approach to do OVS
and/or kernel development check out the following
[document](README_DEVELOPMENT.md). It also has some simple traffic
test to see throughput performance.
