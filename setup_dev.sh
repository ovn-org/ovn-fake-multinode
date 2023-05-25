#!/bin/bash
#
#  Copyright 2020, Eelco Chaudron
#
#  Licensed under the Apache License, Version 2.0 (the "License");
#  you may not use this file except in compliance with the License.
#  You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
#  Unless required by applicable law or agreed to in writing, software
#  distributed under the License is distributed on an "AS IS" BASIS,
#  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#  See the License for the specific language governing permissions and
#  limitations under the License.
#
#  Files name:
#    setup_dev.sh
#
#  Description:
#    Simple script to setup a dev environment for OVN multinode
#
#  Author:
#    Eelco Chaudron
#
#  Initial Created:
#    26 June 2020
#
#  Notes:
#    Once the vagrant image is up and resized, do the following to
#    start the traffic for the first time:
#
#      sudo /vagrant/setup_dev.sh -t
#
#    Next time you can skip the package installation/update do:
#
#      sudo /vagrant/setup_dev.sh -p -t
#
#    To build a customer kernel edit the build_install_kernel() function
#    below to use and build your specific kernel, and restart vagrant:
#
#      sudo /vagrant/setup_dev.sh -p -c -k
#      exit
#      vagrant halt && vagrant up
#
#    To build a custom OVS image do the following. You will need to restart the
#    ovn cluster also as the container image is using the new OVS:
#
#      sudo /vagrant/setup_dev.sh -o -t
#


#
# Error handling
#
set -e
trap 'LAST_COMMAND=$CURRENT_COMMAND; CURRENT_COMMAND=$BASH_COMMAND' DEBUG
trap 'echo "ERROR: \"${LAST_COMMAND}\" command filed with exit code $?."' ERR

#
# Usage
#
function usage()
{
    echo -e "\nUsage: $0 [arguments] \n"
    echo "  -c    Skip OVN cluster start"
    echo "  -C    Skip OVN/OVS configuration"
    echo "  -h    Show this help page"
    echo "  -k    Build and install Linux net-next kernel"
    echo "  -K    Build and install Linux RHEL kernel"
    echo "  -o    Build and install OVS on the ovn-chassis nodes"
    echo "  -p    Skip package update and installation"
    echo "  -t    Start traffic"
}


function check_system()
{
    #
    # Due to a lot of issues with vagrant on Fedora32 (cant install the vagrant.io
    # version as it has problems building vagrant-libvirt, and the default package
    # version does not allow you to use an external disk, BZ1706289). We decided to
    # manually extend the vagrant partition once build :(
    #
    if [ "$(df / --output=size | sed -n 2p)" -lt "12474496" ]; then
        echo "ERROR: You should increase your vagrant partition !!"
        echo "Do the following:"
        echo "  vagrant halt"
        echo "  qemu-img resize ~/.local/share/libvirt/images/ovn-fake-<XXX>.img +100G"
        echo "  vagrant up && vagrant ssh"
        echo "  echo \", +\" | sudo sfdisk -N 1 /dev/vda --no-reread"
        echo "  sudo partprobe"
        echo "  sudo sudo xfs_growfs /"
        exit
    fi

    #
    # Work from the /vagrant directory
    #
    if ! [ -d "/vagrant" ]; then
        echo "ERROR: The /vagrant directory does not exists, make sure it's mounted!"
        exit
    fi
    cd /vagrant || exit;

    #
    # Check if we are root
    #
    if [ "$EUID" -ne 0 ]; then
        echo "ERROR: Please run setup script as root in the Vagrant VM!!"
        exit
    fi
}

#
# Create tmux configuration
#
function create_tmux_config()
{
    if ! [ -f "/root/.tmux.conf" ]; then
        cat > /root/.tmux.conf << EOF
# Remove short-cut delay
set -sg escape-time 1

# Stop renaming tmux windows
set -g allow-rename off

# Set indexes starting at 1, making it easier to use the window by number
set -g base-index 1
setw -g pane-base-index 1

# Reload config with ^b r
bind r source-file ~/.tmux.conf \; display "Reloaded \"~/.tmux.conf!\""

# Status bar options
set -g status-interval 10
set -g status-left '[#(who | cut -d " " -f1)@#h] '
set -g status-left-length 20
set -g status-right '"#{=39:pane_title}" %H:%M'
set -g status-right-length 50
EOF
        cp ~/.tmux.conf /home/vagrant/
        chown vagrant /home/vagrant/.tmux.conf
    fi
}


#
# Install additional packages needed to build OVS and the kernel. There might
# be some overkill here, but it will make live easy in the long run ;)
#
# NOTE: the rpcbind packages update takes long to complete!
function install_packages()
{
    dnf -y update
    dnf install -y \
        aspell \
        aspell-en \
        autoconf \
        automake \
        bc \
        bison \
        ccache \
        checkpolicy \
        clang \
        cmake \
        cscope \
        dwarves \
        elfutils-devel \
        elfutils-libelf-devel \
        emacs-nox \
        flex \
        freetype-devel \
        gcc \
        gcc-c++ \
        gdb \
        git \
        intltool \
        kernel-devel \
        libcap-ng \
        libcap-ng-devel \
        libqhull \
        libtool \
        libunwind-devel \
        lksctp-tools \
        lksctp-tools-devel \
        make \
        man \
        man-pages \
        numactl-devel \
        openssl \
        openssl-devel \
        perf \
        procps-ng \
        psmisc \
        python3 \
        python3-devel \
        rpm-build \
        selinux-policy-devel \
        sysstat \
        systemd-units \
        tcpdump \
        time \
        tmux \
        unbound-devel \
        wget \
        zeromq-devel \
        zlib-devel

    dnf clean all
}


#
# For some test tools we would like to build uperf, so check it out if its
# not yet build and available.
#
function install_uperf()
{
    if ! [ -d "/vagrant/uperf_git" ]; then
        git clone https://github.com/uperf/uperf.git uperf_git
    fi

    if ! [ -f "/vagrant/uperf_git/src/uperf" ]; then
        cd /vagrant/uperf_git/ || exit
        ./configure
        make -j "$(nproc)"
        cd /vagrant/ || exit
        chown -R vagrant ./uperf_git
    fi

    if ! [ -d "/vagrant/bench-uperf_git" ]; then
        git clone https://github.com/perftool-incubator/bench-uperf bench-uperf_git
        sed -i 's/^exec >uperf-client-stderrout.txt/#exec >uperf-client-stderrout.txt/g' ./bench-uperf_git/uperf-client
        sed -i 's/^exec 2>&1/#exec 2>&1/g' ./bench-uperf_git/uperf-client
        chown -R vagrant ./bench-uperf_git
    fi
}


#
# Build and install OVS if requested
#
function build_install_ovs()
{
    cd /vagrant/ovs || exit

    if ! [ -f "/vagrant/ovs/Makefile.in" ]; then
        ./boot.sh
    fi

    if ! [ -f "/vagrant/ovs/Makefile" ]; then
        ./configure --localstatedir="/var" --sysconfdir="/etc" --prefix="/usr" \
                    --enable-ssl --disable-libcapng \
                    CFLAGS="-g -O2 -fno-omit-frame-pointer"
    fi

    # We will always make ;)
    make "-j$(nproc)" V=0

    cd /vagrant || exit
    chown -R vagrant ./ovs

    # If local build is successful we re-create the containers.
    /vagrant/ovn_cluster.sh build

    if [ "$SKIP_OVN_START" -eq "1" ]; then
        echo "WARNING: Restart the cluster to use new OVS in container!!"
    fi
}


#
# Build and install kernel if requested
#
function build_install_kernel()
{
    if ! [ -d "/vagrant/pahole_git" ];then
        git clone git://git.kernel.org/pub/scm/devel/pahole/pahole.git pahole_git
        cd pahole_git;
        mkdir build
        cd build
        cmake -D__LIB=lib ..
        make install
        cp pahole /usr/local/bin/pahole
        cd /vagrant
    fi

    if ! [ -d "/vagrant/kernel_git" ]; then
        runuser -u vagrant -- git clone git://git.kernel.org/pub/scm/linux/kernel/git/netdev/net-next.git kernel_git
    fi

    cd kernel_git || exit

    if ! [ -f "/vagrant/kernel_git/.config" ]; then
        runuser -u vagrant -- cp /boot/config-"$(uname -r)" .config
    fi

    runuser -u vagrant -- scripts/config -d CONFIG_MODULE_SIG
    runuser -u vagrant -- scripts/config -d CONFIG_SYSTEM_TRUSTED_KEYS
    runuser -u vagrant -- make olddefconfig
    runuser -u vagrant -- make -j "$(nproc)" bzImage
    runuser -u vagrant -- make -j "$(nproc)" modules
    make modules_install
    make install

    cd /vagrant || exit

    echo "Select the kernel to BOOT, and reboot the REBOOT vagrant node to "
    echo "activate new kernel!! You can do this with the following:"
    echo " sudo grubby --info=ALL | grep -E \"title=|index=\""
    echo " sudo grubby --set-default-index=1"
    exit
}

#
# Build and install RHEL kernel if requested
#
function build_install_kernel_rhel()
{
    if ! [ -d "/vagrant/kernel_git" ]; then
        runuser -u vagrant -- git clone git://git.host.prod.eng.bos.redhat.com/kernel-rhel.git kernel_git
        runuser -u vagrant -- git checkout rhel-8.3.0
    fi

    if ! [ -f "/vagrant/rhel-kernel" ]; then
        echo "ERROR: To build the kernel, manually copy the rhel-kernel script!"
        exit
    fi

    cd kernel_git || exit

    if ! [ -f "/vagrant/kernel_git/.config" ]; then
        #
        # We will use --fullmod as not doing this had lead to odd issues
        # with missing modules, causing boot problem. Even with --module VETH
        # --module OPENVSWITCH --module GENEVE --module OPENVSWITCH_GENEV
        #
        runuser -u vagrant -- /vagrant/rhel-kernel config --fullmod --host localhost
    fi
    runuser -u vagrant -- /vagrant/rhel-kernel build
    /vagrant/rhel-kernel install --prune never --host localhost

    cd /vagrant || exit

    echo "REBOOT vagrant node to activate new kernel!!"
    exit
}


#
# Start the OVN containers
#
function start_ovn_cluster()
{
    /usr/share/openvswitch/scripts/ovs-ctl --system-id=testovn start
    /vagrant/ovn_cluster.sh stop || true
    /vagrant/ovn_cluster.sh start
}


#
# Start test traffic...
#
function start_traffic()
{
    # Start uperf server in tmux
    if runuser -l vagrant -c "tmux has-session -t uperf_server" 2>/dev/null
    then
        echo "- uperf tmux session running, please check!!"
    else
        podman exec ovn-chassis-2 dnf install -y lksctp-tools
        echo "- Starting uperf server in tmux session \"uperf_server\""
        runuser -l vagrant -c /vagrant/provisioning/start_traffic_server.sh
    fi

    # Start traffic in tmux session
    if runuser -l vagrant -c "tmux has-session -t traffic" 2>/dev/null
    then
        echo "- Traffic tmux session running, please check!!"
    else
        podman exec ovn-chassis-1 dnf install -y lksctp-tools
        echo "- Starting traffic in tmux session \"traffic\""
        runuser -l vagrant -c /vagrant/provisioning/start_traffic.sh
    fi
}


#
# Some additional settings are configure here
#
function configure_ovn()
{
    ! podman exec ovn-central ovn-nbctl acl-add sw0 to-lport 100 "ip4.src==10.128.2.2" allow-related
    podman exec ovn-chassis-1 ip netns exec sw0p1 ip link set dev sw0p1 mtu 1440
    podman exec ovn-chassis-1 ip netns exec sw0p3 ip link set dev sw0p3 mtu 1440
    podman exec ovn-chassis-2 ip netns exec sw0p4 ip link set dev sw0p4 mtu 1440
    podman exec ovn-chassis-2 ip netns exec sw1p1 ip link set dev sw1p1 mtu 1440
}


#
# Main script starts here...
#
SKIP_PACKAGES=0
SKIP_OVN_START=0
SKIP_OVN_CONFIG=0
BUILD_KERNEL=0
BUILD_KERNEL_RHEL=0
BUILD_OVS=0
START_TRAFFIC=0

while getopts "cChkKopt" opt
do
    case $opt in
    (c) SKIP_OVN_START=1 ;;
    (C) SKIP_OVN_CONFIG=1 ;;
    (h) usage && exit ;;
    (k) BUILD_KERNEL=1 ;;
    (K) BUILD_KERNEL_RHEL=1 ;;
    (o) BUILD_OVS=1 ;;
    (p) SKIP_PACKAGES=1 ;;
    (t) START_TRAFFIC=1 ;;
    (*) printf "Unknown option '-%s'\n" "$opt" && usage && exit 1 ;;
    esac
done

check_system
create_tmux_config
[ "$SKIP_PACKAGES" -eq "0" ] && install_packages
install_uperf

[ "$BUILD_KERNEL" -eq "1" ] && build_install_kernel
[ "$BUILD_KERNEL_RHEL" -eq "1" ] && build_install_kernel_rhel
[ "$BUILD_OVS" -eq "1" ] && build_install_ovs
[ "$SKIP_OVN_START" -eq "0" ] && start_ovn_cluster
[ "$SKIP_OVN_CONFIG" -eq "0" ] && configure_ovn
[ "$START_TRAFFIC" -eq "1" ] && start_traffic
