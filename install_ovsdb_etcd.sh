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

if [[ "${USE_OVSDB_ETCD}" = "yes" ]]; then
    mkdir -p /root/

    # Install latest Go version
    mkdir -p $HOME/go/src
    git clone https://github.com/udhos/update-golang.git
    pushd update-golang
    ./update-golang.sh
    popd
    rm -rf ./update-golang
    
    export GOPATH=$HOME/go
    export PATH=$PATH:$GOPATH/bin
    export PATH=$PATH:/usr/local/go/bin
    export PATH=$PATH:$HOME/bin

    pushd $GOPATH/src
    git clone https://github.com/IBM/ovsdb-etcd.git
    pushd ovsdb-etcd
    make build

    cp pkg/cmd/server/server /root/ovsdb_etcd_server
    mkdir -p /var/log/ovn
    popd
    rm -rf ./ovsdb-etcd
    popd
fi
