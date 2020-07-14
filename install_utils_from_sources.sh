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

install_utils=$1
if [ "$install_utils" != "yes" ]; then
    exit 0
fi

# Use this script to install any utilities from sources.

mkdir -p /root/utilities

# Install uperf
pushd /root/utilities
git clone https://github.com/uperf/uperf.git uperf_git
pushd uperf_git
./configure --prefix=/root/utilities/uperf_install
make -j$(($(nproc) + 1))
make install
popd

git clone https://github.com/perftool-incubator/bench-uperf bench-uperf_git
sed -i 's/^exec >uperf-client-stderrout.txt/#exec >uperf-client-stderrout.txt/g' ./bench-uperf_git/uperf-client
sed -i 's/^exec 2>&1/#exec 2>&1/g' ./bench-uperf_git/uperf-client

popd
