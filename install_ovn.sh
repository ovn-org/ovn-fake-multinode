#!/bin/bash
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at:
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -o xtrace
set -o errexit

use_ovn_rpm=$1
use_ovn_debs=$2
extra_optimize=$3

# When system's python environment is marked as "Externally managed"
# (PEP 668), this variable is needed to allow pip to install
# "global" packages.
export PIP_BREAK_SYSTEM_PACKAGES=1

if [ "$extra_optimize" = "yes" ]; then
    cflags='-g -march=native -O3 -fno-omit-frame-pointer -fPIC'
else
    cflags='-g -O2 -fno-omit-frame-pointer -fPIC'
fi

if [ "$use_ovn_rpm" = "yes" ]; then
    ls ovn*.rpm > /dev/null || exit 1
    dnf install -y /*.rpm
elif [ "$use_ovn_debs" = "yes" ]; then 
    ls ovn*.deb > /dev/null || exit 1
    apt update
    apt install -y /*.deb
else
    mkdir -p /root/ovsdb-etcd/schemas

    # Build OVS binaries and install them.
    cd /ovs
    ./boot.sh
    ./configure --localstatedir="/var" --sysconfdir="/etc" --prefix="/usr" \
        --enable-ssl --disable-libcapng --enable-Werror CFLAGS="${cflags}"
    make -j$(($(nproc) + 1)) V=0
    make install
    cp ./ovsdb/_server.ovsschema /root/ovsdb-etcd/schemas/

    # Install python IDL with built-in C extensions.
    pushd /ovs/python
    pkgcfg_libs="`pkg-config --libs --static libopenvswitch`"
    enable_shared=no \
      extra_cflags="`pkg-config --cflags libopenvswitch`" \
      extra_libs="-Wl,-Bstatic -lopenvswitch -Wl,-Bdynamic ${pkgcfg_libs}" \
      python3 -m pip install --verbose --compile .
    popd #/ovs/python

    # Build OVS libraries from submodule, needed by OVN.
    cd /ovn
    rm -rf ./ovs
    git submodule update --init --depth 1

    cd ./ovs
    # build. Note: no explicit install is needed here.
    ./boot.sh
    ./configure --localstatedir="/var" --sysconfdir="/etc" --prefix="/usr" \
    --enable-ssl --disable-libcapng --enable-Werror CFLAGS="${cflags}"
    make -j$(($(nproc) + 1)) V=0

    cd /ovn
    # build and install
    ./boot.sh
    ./configure --localstatedir="/var" --sysconfdir="/etc" --prefix="/usr" \
    --enable-ssl \
    CFLAGS="${cflags}"
    make -j$(($(nproc) + 1)) V=0
    make install
    cp ./ovn-nb.ovsschema /root/ovsdb-etcd/schemas/
    cp ./ovn-sb.ovsschema /root/ovsdb-etcd/schemas/
fi

# Generate SSL certificates.
cd /
mkdir -p /opt/ovn
OVS_PKI="ovs-pki --dir=/opt/ovn/pki"
$OVS_PKI init
pushd /opt/ovn
$OVS_PKI req+sign ovn switch
popd

# remove unused packages to make the container light weight.
dnf autoremove -y || apt autoremove -y

# Clean all object files
if [ "$use_ovn_rpm" = "no" ] && [ "$use_ovn_debs" = "no" ]; then
    cd /ovs
    make distclean
    cd /ovn
    make distclean
    cd ./ovs
    make distclean
fi
