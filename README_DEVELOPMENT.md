# Using ovn-fake-multinode for development and testing

## Setup the Vagrant environment

This example explains how to use the ovn-fake-multinode environment when doing
an Open vSwitch change, including a kernel module change. This assumes you are
using the Vagrant environment.

First we will checkout the ovn-fake-multinode environment as follows:

```
git clone https://github.com/ovn-org/ovn-fake-multinode.git
cd ovn-fake-multinode
export VM_CPUS=8
export VM_MOUNT_NFS=true
vagrant up && vagrant ssh
```

As there is no simple plugin to re-size the vagrant image with the libvirt
provider, we will manually resize it. This will allow us to store and build
a custom kernel, and meet the additional storage requirements for the
updated container images.

The following set of commands will re-size the image:

```
vagrant halt
qemu-img resize ~/.local/share/libvirt/images/ovn-fake-<XXX>.img +100G
vagrant up && vagrant ssh
echo ", +" | sudo sfdisk -N 1 /dev/vda --no-reread
sudo partprobe
sudo sudo xfs_growfs /
exit
vagrant reload && vagrant ssh
```

**NOTE**: Do not user `vagrant destroy` as it will undo all the work above.


## Running a simple traffic test

All operations in this document are build around the `setup_dev.sh` script:

```
$ ./setup_dev.sh -h

Usage: ./setup_dev.sh [arguments]

  -c    Skip OVN cluster start
  -C    Skip OVN/OVS configuration
  -h    Show this help page
  -k    Build and install Linux kernel
  -o    Build and install OVS on the ovn-chassis nodes
  -p    Skip package update and installation
  -t    Start traffic
```

Running the simple test which included some basic traffic, and an _uPerf_ test,
do the following:

```
sudo ./setup_dev.sh -t
```

This will open two _tmux_ sessions, one for the _uPerf_ server (in the
background) and one for the traffic itself, which is put on the foreground.

**NOTE**: The script will try to install/update RPM packages. This is only
required for the first run. If you would like to skip it for other invocations
of the script, use the -p option.


## Building the upstream kernel

To build the kernel simply do the following on the vagrant VM:

```
cd /vagrant
sudo ./setup_dev.sh -p -c -k
```

This will do the following:

- Clone the net-next Linux kernel if not already cloned.
- Copy the current systems .config if a .config does not already exist.
- Build and install the kernel.

Once this is done, select the newly installed kernel, and restart:

```

[vagrant@ovnhostvm vagrant]$ sudo grubby --info=ALL | grep -E "title=|index="
index=0
title="CentOS Linux (4.18.0-80.el8.x86_64) 8 (Core)"
index=1
title="CentOS Linux (5.8.0-rc4+) 8 (Core)"
index=2
title="CentOS Linux (4.18.0-193.6.3.el8_2.x86_64) 8 (Core)"

[vagrant@ovnhostvm vagrant]$ sudo grubby --set-default-index=1
The default is /boot/loader/entries/c10cced2554d4cc6bb81b358cdb1b871-5.8.0-rc4+.conf with index 1 and kernel /boot/vmlinuz-5.8.0-rc4+

[vagrant@ovnhostvm vagrant]$ exit
logout
Connection to 192.168.122.62 closed.
[ebuild:~/ovn-fake-multinode]$ vagrant reload && vagrant ssh
...
...
Last login: Mon Jul 13 14:00:18 2020 from 192.168.122.1
[vagrant@ovnhostvm ~]$ uname -a
Linux ovnhostvm 5.8.0-rc4+ #2 SMP Mon Jul 13 13:59:55 UTC 2020 x86_64 x86_64 x86_64 GNU/Linux
```


## Building Open vSwitch

Open vSwitch is already built and deployed by the ovn_cluster.sh script. Here we
just explain what to do to re-build/re-deploy OVS after you made a change.

This is straight forward, make your changes to the `/vagrant/ovs` directory,
and execute the following:

```
sudo ./setup_dev.sh -p -c -o
```

If the build is successful you can either quickly restart you vagrant VM,
and try the traffic test:

```
exit
vagrant reload && vagrant ssh
sudo ./setup_dev.sh -p -t
```

OR

```
sudo ./ovn_cluster.sh stop
sudo ./ovn_cluster.sh start
sudo ./setup_dev.sh -p -t
```
