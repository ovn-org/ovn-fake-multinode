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
# OVN_SB_PORT - ovn south db port (default 6642)
ovn_sb_port=${OVN_SB_PORT:-6642}
ovsdb_etcd_schemas_dir=${OVSDB_ETCD_SCHEMAS_DIR:-/root/ovsdb-etcd/schemas}
ovsdb_etcd_prefix=${OVSDB_ETCD_PREFIX:-"ovsdb"}
ovsdb_etcd_sb_log_level=${OVSDB_ETCD_SB_LOG_LEVEL:-"3"}
ovsdb_etcd_sb_unix_socket=${OVSDB_ETCD_SB_UNIX_SOCKET:-"/var/run/ovn/ovnsb_db.sock"}
OVN_LOGDIR=/var/log/ovn
sb_pid_file=${OVN_LOGDIR}/ovnsb_etcd.pid
sb_cpuprofile_file=${OVN_LOGDIR}/sb_cpuprofile.prof

function start_sb_ovsdb_etcd() {
    echo "================= start sb-ovsdb-etcd server ============================ "
    /root/ovsdb_etcd_server -logtostderr=false -log_file=${OVN_LOGDIR}/sb-ovsdb-etcd.log -v=${ovsdb_etcd_sb_log_level} -tcp-address=:${ovn_sb_port} \
    -unix-address=${ovsdb_etcd_sb_unix_socket} -etcd-members=${ovsdb_etcd_members} -schema-basedir=${ovsdb_etcd_schemas_dir} \
    -database-prefix=${ovsdb_etcd_prefix} -service-name=sb -schema-file=ovn-sb.ovsschema -pid-file=${sb_pid_file} \
    -load-server-data=false -cpu-profile=${sb_cpuprofile_file} -keepalive-time=6s -keepalive-timeout=20s
}

start_sb_ovsdb_etcd &> /var/log/ovn/sb-ovsdb-etcd-start.log &
