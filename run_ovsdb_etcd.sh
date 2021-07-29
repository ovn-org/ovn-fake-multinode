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

# OVSDB-etcd variables
ovsdb_etcd_members=${OVSDB_ETCD_MEMBERS:-"localhost:2479"}
ovsdb_etcd_max_txn_ops=${OVSDB_ETCD_MAX_TXN_OPS:-"5120"}                        # etcd default is 128
ovsdb_etcd_max_request_bytes=${OVSDB_ETCD_MAX_REQUEST_BYTES:-"157286400"}       # 150 MByte
ovsdb_etcd_warning_apply_duration=${OVSDB_ETCD_WARNING_APPLY_DURATION:-"1s"}    # etcd default is 100ms
ovsdb_etcd_election_timeout=${OVSDB_ETCD_ELECTION_TIMEOUT:-"1000"}              # etcd default
ovsdb_etcd_quota_backend_bytes=${OVSDB_ETCD_QUOTA_BACKEND_BYTES:-"8589934592"}  # 8 GByte
# OVN_NB_PORT - ovn north db port (default 6641)
ovn_nb_port=${OVN_NB_PORT:-6641}
# OVN_SB_PORT - ovn south db port (default 6642)
ovn_sb_port=${OVN_SB_PORT:-6642}
ovsdb_etcd_schemas_dir=${OVSDB_ETCD_SCHEMAS_DIR:-/root/ovsdb-etcd/schemas}
ovsdb_etcd_prefix=${OVSDB_ETCD_PREFIX:-"ovsdb"}
ovsdb_etcd_nb_log_level=${OVSDB_ETCD_NB_LOG_LEVEL:-"6"}
ovsdb_etcd_sb_log_level=${OVSDB_ETCD_SB_LOG_LEVEL:-"6"}
ovsdb_etcd_nb_unix_socket=${OVSDB_ETCD_NB_UNIX_SOCKET:-"/var/run/ovn/ovnnb_db.sock"}
ovsdb_etcd_sb_unix_socket=${OVSDB_ETCD_SB_UNIX_SOCKET:-"/var/run/ovn/ovnsb_db.sock"}
OVN_LOGDIR=/var/log/ovn
nb_pid_file=${OVN_LOGDIR}/ovnnb_etcd.pid
sb_pid_file=${OVN_LOGDIR}/ovnsb_etcd.pid

function start_etcd() {
    echo "================= start etcd server ============================ "
    /usr/local/bin/etcd --data-dir /etc/openvswitch/ \
    --listen-peer-urls http://localhost:2480 \
    --listen-client-urls http://localhost:2479 \
    --advertise-client-urls http://localhost:2479 \
    --max-txn-ops ${ovsdb_etcd_max_txn_ops} \
    --max-request-bytes ${ovsdb_etcd_max_request_bytes} \
    --experimental-txn-mode-write-with-shared-buffer=true \
    --experimental-warning-apply-duration=${ovsdb_etcd_warning_apply_duration} \
    --election-timeout=${ovsdb_etcd_election_timeout} \
    --quota-backend-bytes=${ovsdb_etcd_quota_backend_bytes}
}

start_etcd &> /var/log/ovn/etcd.log &
