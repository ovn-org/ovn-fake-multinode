#!/bin/sh
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

# get ovs source always from master as its needed as dependency
cd /ovs
# build and install
./boot.sh
./configure --localstatedir="/var" --sysconfdir="/etc" --prefix="/usr" \
--enable-ssl --disable-libcapng
make -j$(($(nproc) + 1)) V=0
make install

cd /ovn
# build and install
./boot.sh
./configure --localstatedir="/var" --sysconfdir="/etc" --prefix="/usr" \
--enable-ssl --with-ovs-source=/ovs/ --with-ovs-build=/ovs/
make -j$(($(nproc) + 1)) V=0
make install

# remove unused packages to make the container light weight.
for i in $(package-cleanup --leaves --all);
    do dnf remove -y $i
done
dnf autoremove -y

rm -rf /ovs /ovn
