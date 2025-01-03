#!/bin/bash

[ $EUID -eq 0 ] || { echo 'must be root' >&2; exit 1; }

#set -o xtrace
set -o errexit

RUNC_CMD="${RUNC_CMD:-podman}"

CENTRAL_IMAGE=${CENTRAL_IMAGE:-"ovn/ovn-multi-node:latest"}
CHASSIS_IMAGE=${CHASSIS_IMAGE:-"ovn/ovn-multi-node:latest"}
GW_IMAGE=${GW_IMAGE:-"ovn/ovn-multi-node:latest"}
RELAY_IMAGE=${RELAY_IMAGE:-"ovn/ovn-multi-node:latest"}

USE_OVN_RPMS="${USE_OVN_RPMS:-no}"
USE_OVN_DEBS="${USE_OVN_DEBS:-no}"
EXTRA_OPTIMIZE="${EXTRA_OPTIMIZE:-no}"
OS_BASE=${OS_BASE:-"fedora"}
OS_IMAGE=${OS_IMAGE:-"quay.io/fedora/fedora:latest"}
OS_IMAGE_PULL_RETRIES=${OS_IMAGE_PULL_RETRIES:-40}
OS_IMAGE_PULL_INTERVAL=${OS_IMAGE_PULL_INTERVAL:-5}
USE_OVSDB_ETCD=${USE_OVSDB_ETCD:-no}
CHASSIS_PREFIX="${CHASSIS_PREFIX:-ovn-chassis-}"
GW_PREFIX="ovn-gw-"

CENTRAL_COUNT=${CENTRAL_COUNT:-1}
CENTRAL_PREFIX="${CENTRAL_PREFIX:-ovn-central-az}"
CENTRAL_NAME="${CENTRAL_NAME:-}"
CENTRAL_NAMES=()

CHASSIS_COUNT=${CHASSIS_COUNT:-2}
CHASSIS_NAMES=()

GW_COUNT=${GW_COUNT:-1}
GW_NAMES=()

OVN_BR="br-ovn"
OVN_EXT_BR="br-ovn-ext"
OVN_BR_CLEANUP="${OVN_BR_CLEANUP:-yes}"

OVN_SRC_PATH="${OVN_SRC_PATH:-}"
OVS_SRC_PATH="${OVS_SRC_PATH:-}"

OVNCTL_PATH=/usr/share/ovn/scripts/ovn-ctl

IP_HOST=${IP_HOST:-170.168.0.0}
IP_CIDR=${IP_CIDR:-16}
IP_START=${IP_START:-170.168.0.2}

OVN_DB_CLUSTER="${OVN_DB_CLUSTER:-no}"
OVN_MONITOR_ALL="${OVN_MONITOR_ALL:-no}"

RELAY_COUNT=${RELAY_COUNT:-0}
RELAY_NAMES=( )

OVN_START_IC_DBS=${OVN_START_IC_DBS:-yes}
CENTRAL_IC_IP="${CENTRAL_IC_IP:-}"
CENTRAL_IC_ID="${CENTRAL_IC_ID:-}"

# Controls the type of OVS datapath to be used.
# Possible values:
# - 'system' for the kernel datapath.
# - 'netdev' for the userspace datapath.
# See 'datapath_type' in:
# https://man7.org/linux/man-pages/man5/ovs-vswitchd.conf.db.5.html#Bridge_TABLE
OVN_DP_TYPE="${OVN_DP_TYPE:-system}"

ENABLE_SSL="${ENABLE_SSL:=yes}"
ENABLE_ETCD="${ENABLE_ETCD:=no}"
REMOTE_PROT=ssl

if [ "$ENABLE_SSL" != "yes" ]; then
    REMOTE_PROT=tcp
fi

CREATE_FAKE_VMS="${CREATE_FAKE_VMS:-yes}"

SSL_CERTS_PATH="/opt/ovn"

FAKENODE_MNT_DIR="${FAKENODE_MNT_DIR:-/tmp/ovn-multinode}"
INSTALL_UTILS_FROM_SOURCES="${INSTALL_UTILS_FROM_SOURCES:-no}"

OVN_NBDB_SRC=${OVN_NBDB_SRC}
OVN_SBDB_SRC=${OVN_SBDB_SRC}

function set_node_names() {
    if [ "x$CENTRAL_NAME" == "x" ]; then
        for (( i=1; i<=CENTRAL_COUNT; i++ )); do
            CENTRAL_NAMES+=( "${CENTRAL_PREFIX}${i}" )
        done
    else
        CENTRAL_NAMES+=( "$CENTRAL_NAME" )
    fi

    for (( i=1; i<=CHASSIS_COUNT; i++ )); do
        CHASSIS_NAMES+=( "${CHASSIS_PREFIX}${i}" )
    done

    for (( i=1; i<=GW_COUNT; i++ )); do
        GW_NAMES+=( "${GW_PREFIX}${i}" )
    done

    for central_name in "${CENTRAL_NAMES[@]}"; do
        for (( j=1; j<=RELAY_COUNT; j++ )); do
            RELAY_NAMES+=( "${central_name}-relay-${j}" )
        done
    done
}

function count-central() {
    local filter=${1:-}
    count-containers "${CENTRAL_PREFIX}" "${filter}"
}

function count-chassis() {
    local filter=${1:-}
    count-containers "${CHASSIS_PREFIX}" "${filter}"
}

function count-gw() {
    local filter=${1:-}
    count-containers "${GW_PREFIX}" "${filter}"
}

function count-containers() {
  local name=$1
  local filter=${2:-}
  local count=0

  # remove any whitespace from the container name
  name=$(echo $name | sed 's/ //g')

  for cid in $( ${RUNC_CMD} ps -qa --filter "name=${name}" $filter); do
    (( count += 1 ))
  done

  echo "$count"
}

function start-container() {
  local image=$1
  local name=$2
  local vagrant_mount=""

  local volumes run_cmd
  volumes=""

  if [ -d "/vagrant" ]; then
      vagrant_mount="-v /vagrant:/vagrant"
  fi

  ${RUNC_CMD} run  -dt ${volumes} -v "${FAKENODE_MNT_DIR}:/data" --privileged \
              $vagrant_mount --name="${name}" --hostname="${name}" \
              "${image}" > /dev/null

  # Make sure ipv6 in container is enabled if we will be using it
  if [ "$IPV6_UNDERLAY" = "yes" ]; then
    ${RUNC_CMD} exec ${name} sysctl --quiet -w net.ipv6.conf.all.disable_ipv6=0
    ${RUNC_CMD} exec ${name} sysctl --quiet -w net.ipv6.conf.default.disable_ipv6=0
  fi
}

function stop-container() {
    local cid=$1
    ${RUNC_CMD} rm -f --volumes "${cid}" > /dev/null
}

function stop() {
    for i in $(seq $CENTRAL_COUNT); do
        ip netns delete ovnfake-ext$i || :
        ip netns delete ovnfake-int$i || :
    done
    if [ "${OVN_BR_CLEANUP}" == "yes" ]; then
        ovs-vsctl --if-exists del-br $OVN_BR || exit 1
        ovs-vsctl --if-exists del-br $OVN_EXT_BR || exit 1
    else
        for name in "${CENTRAL_NAMES[@]}"; do
            if [ "$OVN_DB_CLUSTER" = "yes" ]; then
                del-ovs-container-ports ${name}-1
                del-ovs-container-ports ${name}-2
                del-ovs-container-ports ${name}-3
            else
                del-ovs-container-ports ${name}
            fi
        done
        for name in "${RELAY_NAMES[@]}"; do
            del-ovs-container-ports ${name}
        done
        for name in "${GW_NAMES[@]}"; do
            del-ovs-container-ports ${name}
        done
        for name in "${CHASSIS_NAMES[@]}"; do
            del-ovs-container-ports ${name}
        done
    fi

    echo "Stopping OVN cluster"
    # Delete the containers
    for cid in $( ${RUNC_CMD} ps -qa --filter "name=${CENTRAL_PREFIX}|${GW_PREFIX}|${CHASSIS_PREFIX}" ); do
       stop-container ${cid}
    done
}

function setup-ovs-in-host() {
    ovs-vsctl br-exists $OVN_BR || ovs-vsctl add-br $OVN_BR || exit 1
    ovs-vsctl br-exists $OVN_BR || ovs-vsctl add-br $OVN_EXT_BR || exit 1
}

function add-ovs-container-ports() {
    ovn_central=$1
    ip_range=$IP_HOST
    cidr=$IP_CIDR
    ip_start=$IP_START

    br=$OVN_BR
    eth=eth1

    ip_index=0
    if [ "$ovn_central" == "yes" ]; then
        for i in $(seq 3); do
            echo -n > _ovn_central_$i
        done
        echo -n > _ovn_remote

        for name in "${CENTRAL_NAMES[@]}"; do
            if [ "$OVN_DB_CLUSTER" = "yes" ]; then
                ip1=$(./ip_gen.py $ip_range/$cidr $ip_start $ip_index)
                ./ovs-runc add-port $br $eth ${name}-1 --ipaddress=${ip1}/${cidr}
                echo "$name $ip1" >> _ovn_central_1
                (( ip_index += 1))

                ip2=$(./ip_gen.py $ip_range/$cidr $ip_start $ip_index)
                ./ovs-runc add-port $br $eth ${name}-2 --ipaddress=${ip2}/${cidr}
                echo "$name $ip2" >> _ovn_central_2
                (( ip_index += 1))

                ip3=$(./ip_gen.py $ip_range/$cidr $ip_start $ip_index)
                ./ovs-runc add-port $br $eth ${name}-3 --ipaddress=${ip3}/${cidr}
                echo "$name $ip3" >> _ovn_central_3
                (( ip_index += 1))

                echo "$name ${REMOTE_PROT}:$ip1:6642,${REMOTE_PROT}:$ip2:6642,${REMOTE_PROT}:$ip3:6642" >> _ovn_remote
            else
                ip=$(./ip_gen.py $ip_range/$cidr $ip_start $ip_index)
                ./ovs-runc add-port $br $eth ${name} --ipaddress=${ip}/${cidr}
                echo "$name ${REMOTE_PROT}:$ip:6642" >> _ovn_remote
                (( ip_index += 1))
            fi
        done

        for name in "${GW_NAMES[@]}"; do
            ip=$(./ip_gen.py $ip_range/$cidr $ip_start $ip_index)
            ./ovs-runc add-port $br $eth ${name} --ipaddress=${ip}/${cidr}
            (( ip_index += 1))
        done

        if [ "$RELAY_COUNT" -gt 0 ]; then
            echo -n > _ovn_relay_remotes

            relay_remotes=""
            last_az="az1"

            for name in "${RELAY_NAMES[@]}"; do
                relay_az=$(echo $name | awk -F- '{print $3}')
                if [ "$relay_az" != "$last_az" ]; then
                    ovn_relay_remotes=$(echo $relay_remotes | cut -c 2-)
                    echo "ovn-central-$last_az $ovn_relay_remotes" >> _ovn_relay_remotes
                    relay_remotes=""
                    last_az="$relay_az"
                fi

                ip=$(./ip_gen.py $ip_range/$cidr $ip_start $ip_index)
                ./ovs-runc add-port $br $eth ${name} --ipaddress=${ip}/${cidr}
                relay_remotes=$relay_remotes",${REMOTE_PROT}:$ip:6642"
                (( ip_index += 1))
            done
            ovn_relay_remotes=$(echo $relay_remotes | cut -c 2-)
            echo "ovn-central-$last_az $ovn_relay_remotes" >> _ovn_relay_remotes

            cat _ovn_remote > _ovn_remote_main_db
            cat _ovn_relay_remotes > _ovn_remote
        fi
    fi

    for name in "${CHASSIS_NAMES[@]}"; do
        ip=$(./ip_gen.py $ip_range/$cidr $ip_start $ip_index)
        ./ovs-runc add-port $br $eth ${name} --ipaddress=${ip}/${cidr}
        (( ip_index += 1))
    done

    if [ "$ovn_central" == "yes" ]; then
        for name in "${CENTRAL_NAMES[@]}"; do
            if [ "$OVN_DB_CLUSTER" = "yes" ]; then
                ./ovs-runc add-port ${OVN_EXT_BR} eth2 ${name}-1
                ./ovs-runc add-port ${OVN_EXT_BR} eth2 ${name}-2
                ./ovs-runc add-port ${OVN_EXT_BR} eth2 ${name}-3
            else
                ./ovs-runc add-port ${OVN_EXT_BR} eth2 ${name}
            fi
        done
        for name in "${RELAY_NAMES[@]}"; do
            ./ovs-runc add-port ${OVN_EXT_BR} eth2 ${name}
        done
        for name in "${GW_NAMES[@]}"; do
            ./ovs-runc add-port ${OVN_EXT_BR} eth2 ${name}
        done
    fi

    for name in "${CHASSIS_NAMES[@]}"; do
        ./ovs-runc add-port ${OVN_EXT_BR} eth2 ${name}
    done
}

function del-ovs-container-ports() {
    local name=$1

    ./ovs-runc del-port $OVN_BR eth1 ${name} || :
    ./ovs-runc del-port $OVN_EXT_BR eth2 ${name} || :
}

function configure-ovn() {
    ovn_central=$1
    ovn_remote=$2
    ovn_monitor_all=$3
    ovn_dp_type=$4

    rm -f ${FAKENODE_MNT_DIR}/configure_ovn.sh

    cat << EOF > ${FAKENODE_MNT_DIR}/configure_ovn.sh
#!/bin/bash

eth=\$1
ovn_remote=\$2
is_gw=\$3
ovn_monitor_all=\$4
ovn_dp_type=\$5

if [ "\$eth" = "" ]; then
    eth=eth1
fi

if [ "\$ovn_remote" = "none" ]; then
    ovn_remote="tcp:170.168.0.2:6642"
fi

ip=\`ip addr show \$eth | grep inet | grep -v inet6 | awk '{print \$2}' | cut -d'/' -f1\`

ovs-vsctl set open . external_ids:ovn-encap-ip=\$ip
ovs-vsctl set open . external-ids:ovn-encap-type=geneve
ovs-vsctl set open . external-ids:ovn-remote=\$ovn_remote
ovs-vsctl set open . external-ids:ovn-openflow-probe-interval=60
ovs-vsctl set open . external-ids:ovn-remote-probe-interval=180000

if [ "\$ovn_monitor_all" = "yes" ]; then
    ovs-vsctl set open . external-ids:ovn-monitor-all=true
fi

ovs-vsctl set open . external-ids:ovn-bridge-datapath-type=\$ovn_dp_type

ovs-vsctl --if-exists del-br br-ex
ovs-vsctl add-br br-ex
ovs-vsctl set Bridge br-ex datapath_type=\$ovn_dp_type
ovs-vsctl set open . external-ids:ovn-bridge-mappings=public:br-ex
if [ "\$is_gw" = 'is_gw' ]; then
    ovs-vsctl set open . external-ids:ovn-cms-options=enable-chassis-as-gw
fi
ovs-vsctl set open_vswitch . external_ids:ovn-is-interconn=true

ip link set eth2 down
ovs-vsctl add-port br-ex eth2
ip link set eth2 up
EOF

    chmod 0755 ${FAKENODE_MNT_DIR}/configure_ovn.sh

    index=1
    if [ "$ovn_central" == "yes" ]; then
        for name in "${GW_NAMES[@]}"; do
            ovn_remote_gw=$ovn_remote
            if [ "$ovn_remote_gw" == "none" -a -e _ovn_remote ]; then
                ovn_remote_gw="$(awk -v idx=$index 'NR==idx {print $2}' _ovn_remote)"
            fi
            ${RUNC_CMD} exec ${name} bash /data/configure_ovn.sh eth1 \
                ${ovn_remote_gw} is_gw ${ovn_monitor_all} ${ovn_dp_type}
                index=$((index % $CENTRAL_COUNT + 1))
        done
    fi

    index=1
    for name in "${CHASSIS_NAMES[@]}"; do
        ovn_remote_ch=$ovn_remote
        if [ "$ovn_remote_ch" == "none" -a -e _ovn_remote ]; then
            ovn_remote_ch="$(awk -v idx=$index 'NR==idx {print $2}' _ovn_remote)"
        fi
        ${RUNC_CMD} exec ${name} bash /data/configure_ovn.sh eth1 \
            ${ovn_remote_ch} not_gw ${ovn_monitor_all} ${ovn_dp_type}
            index=$((index % $CENTRAL_COUNT + 1))
    done
}

function wait-containers() {
    local ovn_central=$1
    echo "Waiting for containers to be up.."
    while : ; do
        local done="1"
        if [ "${ovn_central}" == "yes" ]; then
            for name in "${CENTRAL_NAMES[@]}"; do
                if [ "$OVN_DB_CLUSTER" = "yes" ]; then
                    [[ $(count-containers "${name}-1") == "0" ]] && continue
                    [[ $(count-containers "${name}-2") == "0" ]] && continue
                    [[ $(count-containers "${name}-3") == "0" ]] && continue
                else
                    [[ $(count-containers "${name}") == "0" ]] && continue
                fi
            done
            for name in "${GW_NAMES[@]}"; do
                [[ $(count-containers "${name}") == "0" ]] && done="0" && break
            done
            for name in "${RELAY_NAMES[@]}"; do
                [[ $(count-containers "${name}") == "0" ]] && done="0" && break
            done
            [[ ${done} == "0" ]] && continue
        fi
        for name in "${CHASSIS_NAMES[@]}"; do
            [[ $(count-containers "${name}") == "0" ]] && done="0" && break
        done
        [[ ${done} == "1" ]] && break
    done
}

# Provisions a NB or SB db file on the central nodes.
# Usage: provision-db-file nb|sb <source-db-file>
function provision-db-file() {
    local db=$1
    local src=$2

    for name in "${CENTRAL_NAMES[@]}"; do
        if [ "$OVN_DB_CLUSTER" = "yes" ]; then
            ${RUNC_CMD} cp ${src} ${name}-1:/etc/ovn/ovn${db}_db.db
            ${RUNC_CMD} cp ${src} ${name}-2:/etc/ovn/ovn${db}_db.db
            ${RUNC_CMD} cp ${src} ${name}-3:/etc/ovn/ovn${db}_db.db
        else
            ${RUNC_CMD} cp ${src} ${name}:/etc/ovn/ovn${db}_db.db
        fi
    done
}

# Starts OVN dbs RAFT cluster on ovn-central-1, ovn-central-2 and ovn-central-3
# containers.
function start-db-cluster() {
    local name=$1
    SSL_ARGS=""
    if [ "$ENABLE_SSL" == "yes" ]; then
        SSL_ARGS="--ovn-nb-db-ssl-key=${SSL_CERTS_PATH}/ovn-privkey.pem \
                  --ovn-nb-db-ssl-cert=${SSL_CERTS_PATH}/ovn-cert.pem \
                  --ovn-nb-db-ssl-ca-cert=${SSL_CERTS_PATH}/pki/switchca/cacert.pem \
                  --ovn-sb-db-ssl-key=${SSL_CERTS_PATH}/ovn-privkey.pem \
                  --ovn-sb-db-ssl-cert=${SSL_CERTS_PATH}/ovn-cert.pem \
                  --ovn-sb-db-ssl-ca-cert=${SSL_CERTS_PATH}/pki/switchca/cacert.pem \
                  --ovn-northd-ssl-key=${SSL_CERTS_PATH}/ovn-privkey.pem \
                  --ovn-northd-ssl-cert=${SSL_CERTS_PATH}/ovn-cert.pem \
                  --ovn-northd-ssl-ca-cert=${SSL_CERTS_PATH}/pki/switchca/cacert.pem"
    fi

    central_1_ip=$(awk -v NAME="$name" 'match($0, NAME) {print $2}' _ovn_central_1)
    central_2_ip=$(awk -v NAME="$name" 'match($0, NAME) {print $2}' _ovn_central_2)
    central_3_ip=$(awk -v NAME="$name" 'match($0, NAME) {print $2}' _ovn_central_3)

    ${RUNC_CMD} exec ${name}-1 ${OVNCTL_PATH} --db-nb-addr=${central_1_ip} \
    --db-sb-addr=${central_1_ip} --db-nb-cluster-local-addr=${central_1_ip} \
    --db-nb-cluster-local-proto=${REMOTE_PROT} \
    --db-sb-cluster-local-addr=${central_1_ip} --db-sb-cluster-local-proto=${REMOTE_PROT} \
    --ovn-nb-db-ssl-key=/data/${name}/ovnnb-privkey.pem \
    $SSL_ARGS start_ovsdb

    ${RUNC_CMD} exec ${name}-2 ${OVNCTL_PATH} --db-nb-addr=${central_2_ip}  \
    --db-sb-addr=${central_2_ip} \
    --db-nb-cluster-local-addr=${central_2_ip} --db-nb-cluster-remote-addr=${central_1_ip} \
    --db-sb-cluster-local-addr=${central_2_ip} --db-sb-cluster-remote-addr=${central_1_ip} \
    --db-nb-cluster-local-proto=${REMOTE_PROT} --db-sb-cluster-local-proto=${REMOTE_PROT} \
    --db-nb-cluster-remote-proto=${REMOTE_PROT} --db-sb-cluster-remote-proto=${REMOTE_PROT} \
    $SSL_ARGS start_ovsdb

    ${RUNC_CMD} exec ${name}-3 ${OVNCTL_PATH} --db-nb-addr=${central_3_ip} \
    --db-sb-addr=${central_3_ip}  \
    --db-nb-cluster-local-addr=${central_3_ip} --db-nb-cluster-remote-addr=${central_1_ip} \
    --db-sb-cluster-local-addr=${central_3_ip} --db-sb-cluster-remote-addr=${central_1_ip} \
    --db-nb-cluster-local-proto=${REMOTE_PROT} --db-sb-cluster-local-proto=${REMOTE_PROT} \
    --db-nb-cluster-remote-proto=${REMOTE_PROT} --db-sb-cluster-remote-proto=${REMOTE_PROT} \
    $SSL_ARGS start_ovsdb

    # This can be improved.
    sleep 3

    # Start ovn-northd on all ovn-central nodes. One of the instance gets the lock from
    # SB DB ovsdb-server and becomes active. Most likely ovn-northd in ${name}-1
    # will become active as it is started first.
    # 'ovn-appctl -t ovn-northd status' will give the status of ovn-northd i.e if it
    # has lock and active or not.
    ${RUNC_CMD} exec ${name}-1 ${OVNCTL_PATH}  \
    --ovn-northd-nb-db=${REMOTE_PROT}:${central_1_ip}:6641,${REMOTE_PROT}:${central_2_ip}:6641,${REMOTE_PROT}:${central_3_ip}:6641 \
    --ovn-northd-sb-db=${REMOTE_PROT}:${central_1_ip}:6642,${REMOTE_PROT}:${central_2_ip}:6642,${REMOTE_PROT}:${central_3_ip}:6642 --ovn-manage-ovsdb=no \
    $SSL_ARGS start_northd

    ${RUNC_CMD} exec ${name}-2 ${OVNCTL_PATH}  \
    --ovn-northd-nb-db=${REMOTE_PROT}:${central_1_ip}:6641,${REMOTE_PROT}:${central_2_ip}:6641,${REMOTE_PROT}:${central_3_ip}:6641 \
    --ovn-northd-sb-db=${REMOTE_PROT}:${central_1_ip}:6642,${REMOTE_PROT}:${central_2_ip}:6642,${REMOTE_PROT}:${central_3_ip}:6642 --ovn-manage-ovsdb=no \
    $SSL_ARGS start_northd

    ${RUNC_CMD} exec ${name}-3 ${OVNCTL_PATH}  \
    --ovn-northd-nb-db=${REMOTE_PROT}:${central_1_ip}:6641,${REMOTE_PROT}:${central_2_ip}:6641,${REMOTE_PROT}:${central_3_ip}:6641 \
    --ovn-northd-sb-db=${REMOTE_PROT}:${central_1_ip}:6642,${REMOTE_PROT}:${central_2_ip}:6642,${REMOTE_PROT}:${central_3_ip}:6642 --ovn-manage-ovsdb=no \
    $SSL_ARGS start_northd
}

function start-ovn-ic() {
    if [ "$OVN_START_IC_DBS" = "yes" ]; then
        if [ -z "$CENTRAL_IC_ID" ]; then
            CENTRAL_IC_ID="${CENTRAL_NAMES[0]}"
        fi

        ${RUNC_CMD} exec $CENTRAL_IC_ID ${OVNCTL_PATH}  \
            --db-ic-nb-create-insecure-remote=yes       \
            --db-ic-sb-create-insecure-remote=yes start_ic_ovsdb

        if [ "$OVN_DB_CLUSTER" = "yes" ] && [ -z "$CENTRAL_IC_IP" ]; then
            CENTRAL_IC_IP=$(awk -v NAME="${CENTRAL_NAMES[0]}" 'match($0, NAME) {print $2}' _ovn_central_1)
        elif [ -z "$CENTRAL_IC_IP" ]; then
            [ $RELAY_COUNT -gt 0 ] && REMOTE=_ovn_remote_main_db || REMOTE=_ovn_remote
            CENTRAL_IC_IP=$(awk -v NAME="${CENTRAL_NAMES[0]}" 'match($0, NAME) {print $2}' $REMOTE |awk -F: '{print $2}')
        fi
    elif [ -z "$CENTRAL_IC_IP" ] || [ -z "$CENTRAL_IC_ID" ]; then
        echo "IC DBs not started locally, please specify the IC DBs container name (CENTRAL_IC_ID) and its IP (CENTRAL_IC_IP)"
        exit 1
    fi

    for name in "${CENTRAL_NAMES[@]}"; do
        if [ "$OVN_DB_CLUSTER" = "yes" ]; then
            ${RUNC_CMD} exec ${name}-1 ${OVNCTL_PATH}               \
                --ovn-ic-nb-db=tcp:${CENTRAL_IC_IP}:6645            \
                --ovn-ic-sb-db=tcp:${CENTRAL_IC_IP}:6646 start_ic
            ${RUNC_CMD} exec ${name}-2 ${OVNCTL_PATH}               \
                --ovn-ic-nb-db=tcp:${CENTRAL_IC_IP}:6645            \
                --ovn-ic-sb-db=tcp:${CENTRAL_IC_IP}:6646 start_ic
            ${RUNC_CMD} exec ${name}-3 ${OVNCTL_PATH}               \
                --ovn-ic-nb-db=tcp:${CENTRAL_IC_IP}:6645            \
                --ovn-ic-sb-db=tcp:${CENTRAL_IC_IP}:6646 start_ic
        else
            ${RUNC_CMD} exec ${name} ${OVNCTL_PATH}                 \
                --ovn-ic-nb-db=tcp:${CENTRAL_IC_IP}:6645            \
                --ovn-ic-sb-db=tcp:${CENTRAL_IC_IP}:6646 start_ic
        fi
    done
}

function check-no-central {
    local operation=$1
    local filter=${2:-}
    local message="${3:-Existing central}"
    
    local existing_central=$(count-central "${filter}")
    if (( existing_central > 0 )); then
        echo
        echo "ERROR: Can't ${operation}.  ${message} (${existing_chassis} existing central)"
        exit 1
    fi
}

function check-no-chassis {
    local operation=$1
    local filter=${2:-}
    local message="${3:-Existing chassis}"
    
    local existing_chassis=$(count-chassis "${filter}")
    if (( existing_chassis > 0 )); then
        echo
        echo "ERROR: Can't ${operation}.  ${message} (${existing_chassis} existing chassis)"
        exit 1
    fi
}

function check-no-gw {
    local operation=$1
    local filter=${2:-}
    local message="${3:-Existing gw}"
    
    local existing_gw=$(count-gw "${filter}")
    if (( existing_gw > 0 )); then
        echo
        echo "ERROR: Can't ${operation}.  ${message} (${existing_gw} existing gw)"
        exit 1
    fi
}

function start() {
    echo "Starting OVN cluster"
    ovn_central=$1
    ovn_remote=$2
    ovn_add_chassis=$3

    if [ "x$ovn_central" == "x" ]; then
        ovn_central="yes"
    fi

    # Check that no ovn related containers are running if we're not adding
    # new containers.
    if [ "x$ovn_add_chassis" == "x" ]; then
        ovn_add_chassis="no"
    fi

    if [ "$ovn_central" == "yes" ]; then
        check-no-central "start"
        check-no-gw "start"
    fi

    if [ "$ovn_add_chassis" == "no" ] && [ "${CHASSIS_COUNT}" -gt 0 ]; then
        check-no-chassis "start"
    fi

    setup-ovs-in-host

    mkdir -p ${FAKENODE_MNT_DIR}

    # Create containers
    if [ "$ovn_central" == "yes" ]; then
        for name in "${CENTRAL_NAMES[@]}"; do
            if [ "$OVN_DB_CLUSTER" = "yes" ]; then
                start-container "${CENTRAL_IMAGE}" "${name}-1"
                start-container "${CENTRAL_IMAGE}" "${name}-2"
                start-container "${CENTRAL_IMAGE}" "${name}-3"
            else
                start-container "${CENTRAL_IMAGE}" "${name}"
            fi
        done

        for name in "${GW_NAMES[@]}"; do
            start-container "${GW_IMAGE}" "${name}"
        done
        for name in "${RELAY_NAMES[@]}"; do
            start-container "${RELAY_IMAGE}" "${name}"
        done
    fi

    for name in "${CHASSIS_NAMES[@]}"; do
        start-container "${CHASSIS_IMAGE}" "${name}"
    done

    wait-containers ${ovn_central}

    echo "Adding ovs-ports"
    # Add ovs ports to each of the nodes.
    add-ovs-container-ports ${ovn_central}

    if [ "x$ovn_remote" == "x" ]; then
        ovn_remote="none"
    fi

    # Start OVN db servers on central node
    if [ "$ovn_central" == "yes" ]; then
        if [ -n "${OVN_NBDB_SRC}" ]; then
            provision-db-file nb ${OVN_NBDB_SRC}
        fi

        if [ -n "${OVN_SBDB_SRC}" ]; then
            provision-db-file sb ${OVN_SBDB_SRC}
        fi

        for name in "${CENTRAL_NAMES[@]}"; do
            [ "$OVN_DB_CLUSTER" = "yes" ] && CENTRAL=${name}-1 || CENTRAL=${name}

            if [ "$ENABLE_ETCD" == "yes" ]; then
                CENTRAL=${name}
                echo "Starting ovsdb-etcd in ${name} container"
                ${RUNC_CMD} exec --detach ${name} bash -c "/run_ovsdb_etcd.sh"
                sleep 2
                ${RUNC_CMD} exec --detach ${name} bash -c "/run_ovsdb_etcd_sb.sh"
                ${RUNC_CMD} exec --detach ${name} bash -c "/run_ovsdb_etcd_nb.sh"
                ${RUNC_CMD} exec ${name} ${OVNCTL_PATH} --ovn-manage-ovsdb=no start_northd
            elif [ "$OVN_DB_CLUSTER" = "yes" ]; then
                start-db-cluster ${name}
            else
                ${RUNC_CMD} exec ${CENTRAL} ${OVNCTL_PATH} start_northd
                sleep 2
            fi

            if [ "$ENABLE_SSL" == "yes" ]; then
                ${RUNC_CMD} exec ${CENTRAL} ovn-nbctl set-ssl ${SSL_CERTS_PATH}/ovn-privkey.pem  ${SSL_CERTS_PATH}/ovn-cert.pem ${SSL_CERTS_PATH}/pki/switchca/cacert.pem
                ${RUNC_CMD} exec ${CENTRAL} ovn-sbctl set-ssl ${SSL_CERTS_PATH}/ovn-privkey.pem  ${SSL_CERTS_PATH}/ovn-cert.pem ${SSL_CERTS_PATH}/pki/switchca/cacert.pem
            fi
            ${RUNC_CMD} exec ${CENTRAL} ovn-nbctl set-connection p${REMOTE_PROT}:6641
            ${RUNC_CMD} exec ${CENTRAL} ovn-nbctl set connection . inactivity_probe=180000

            ${RUNC_CMD} exec ${CENTRAL} ovn-nbctl set NB_Global . name=${CENTRAL} \
                options:ic-route-adv=true options:ic-route-learn=true

            ${RUNC_CMD} exec ${CENTRAL} ovn-sbctl set-connection p${REMOTE_PROT}:6642
            ${RUNC_CMD} exec ${CENTRAL} ovn-sbctl set connection . inactivity_probe=180000
        done

        # start ovn-ic dbs
        start-ovn-ic

        for name in "${RELAY_NAMES[@]}"; do
            SSL_ARGS=
            if [ "$ENABLE_SSL" == "yes" ]; then
                SSL_ARGS="--private-key=${SSL_CERTS_PATH}/ovn-privkey.pem \
                          --certificate=${SSL_CERTS_PATH}/ovn-cert.pem \
                          --ca-cert=${SSL_CERTS_PATH}/pki/switchca/cacert.pem \
                          --ssl-protocols=db:OVN_Southbound,SSL,ssl_protocols \
                          --ssl-ciphers=db:OVN_Southbound,SSL,ssl_ciphers"
            fi
            relay_az=$(echo $name | awk -F- '{print $3}')
            ${RUNC_CMD} exec ${name} ovsdb-server -vconsole:off -vfile:info -vrelay:file:dbg \
                --log-file=/var/log/ovn/ovsdb-server-sb.log --remote=punix:/var/run/ovn/ovnsb_db.sock \
                --pidfile=/var/run/ovn/ovnsb_db.pid --unixctl=/var/run/ovn/ovnsb_db.ctl \
                --detach --monitor --remote=db:OVN_Southbound,SB_Global,connections \
                ${SSL_ARGS} relay:OVN_Southbound:$(grep $relay_az _ovn_remote_main_db | awk '{print $2}')
        done

        for name in "${GW_NAMES[@]}"; do
            SSL_ARGS=
            if [ "$ENABLE_SSL" == "yes" ]; then
                SSL_ARGS="--ovn-controller-ssl-key=${SSL_CERTS_PATH}/ovn-privkey.pem --ovn-controller-ssl-cert=${SSL_CERTS_PATH}/ovn-cert.pem --ovn-controller-ssl-ca-cert=${SSL_CERTS_PATH}/pki/switchca/cacert.pem"
            fi
            ${RUNC_CMD} exec ${name} /usr/share/openvswitch/scripts/ovs-ctl start --system-id=${name}
            ${RUNC_CMD} exec ${name} ${OVNCTL_PATH} start_controller ${SSL_ARGS}
        done
    fi

    for name in "${CHASSIS_NAMES[@]}"; do
        SSL_ARGS=
        if [ "$ENABLE_SSL" == "yes" ]; then
            SSL_ARGS="--ovn-controller-ssl-key=${SSL_CERTS_PATH}/ovn-privkey.pem --ovn-controller-ssl-cert=${SSL_CERTS_PATH}/ovn-cert.pem --ovn-controller-ssl-ca-cert=${SSL_CERTS_PATH}/pki/switchca/cacert.pem"
        fi
        ${RUNC_CMD} exec ${name} /usr/share/openvswitch/scripts/ovs-ctl start --system-id=${name}
        ${RUNC_CMD} exec ${name} ${OVNCTL_PATH} start_controller ${SSL_ARGS}
    done

    configure-ovn $ovn_central $ovn_remote ${OVN_MONITOR_ALL} ${OVN_DP_TYPE}
}

function create_fake_vms() {
    az=$1
    [ $2 -gt 1 ] && ic="yes" || ic="no"
    cat << EOF > ${FAKENODE_MNT_DIR}/create_ovn_res.sh
#!/bin/bash

#set -o xtrace
set -o errexit

az=\$1
ic=\$2

ovn-nbctl ls-add sw0\$az

# ovn dhcpd on sw0\$az
ovn-nbctl set logical_switch sw0\$az \
  other_config:subnet="1\$az.0.0.0/24" \
  other_config:exclude_ips="1\$az.0.0.1..1\$az.0.0.2"
ovn-nbctl dhcp-options-create 1\$az.0.0.0/24
CIDR_UUID=\$(ovn-nbctl --bare --columns=_uuid find dhcp_options cidr="1\$az.0.0.0/24")
ovn-nbctl dhcp-options-set-options \$CIDR_UUID \
  lease_time=3600 \
  router=1\$az.0.0.1 \
  server_id=1\$az.0.0.1 \
  server_mac=c0:ff:ee:00:00:01

ovn-nbctl lsp-add sw0\$az sw0\$az-port1
ovn-nbctl lsp-set-addresses sw0\$az-port1 "50:5\$az:00:00:00:03 1\$az.0.0.3 100\$az::3"
ovn-nbctl lsp-add sw0\$az sw0\$az-port2
ovn-nbctl lsp-set-addresses sw0\$az-port2 "50:5\$az:00:00:00:04 1\$az.0.0.4 100\$az::4"

# Create ports in sw0\$az that will use dhcp from ovn
ovn-nbctl lsp-add sw0\$az sw0\$az-port3
ovn-nbctl lsp-set-addresses sw0\$az-port3 "50:5\$az:00:00:00:05 dynamic"
ovn-nbctl lsp-set-dhcpv4-options sw0\$az-port3 \$CIDR_UUID
ovn-nbctl lsp-add sw0\$az sw0\$az-port4
ovn-nbctl lsp-set-addresses sw0\$az-port4 "50:5\$az:00:00:00:06 dynamic"
ovn-nbctl lsp-set-dhcpv4-options sw0\$az-port4 \$CIDR_UUID

# Create the second logical switch with one port
ovn-nbctl ls-add sw1\$az
ovn-nbctl lsp-add sw1\$az sw1\$az-port1
ovn-nbctl lsp-set-addresses sw1\$az-port1 "40:5\$az:00:00:00:03 2\$az.0.0.3 200\$az::3"

# Create a logical router and attach both logical switches
ovn-nbctl lr-add lr\$az
ovn-nbctl lrp-add lr\$az lr\$az-sw0\$az 00:0\$az:00:00:ff:01 1\$az.0.0.1/24 100\$az::a/64
ovn-nbctl lsp-add sw0\$az sw0\$az-lr\$az
ovn-nbctl lsp-set-type sw0\$az-lr\$az router
ovn-nbctl lsp-set-addresses sw0\$az-lr\$az router
ovn-nbctl lsp-set-options sw0\$az-lr\$az router-port=lr\$az-sw0\$az

ovn-nbctl lrp-add lr\$az lr\$az-sw1\$az 00:0\$az:00:00:ff:02 2\$az.0.0.1/24 200\$az::a/64
ovn-nbctl lsp-add sw1\$az sw1\$az-lr\$az
ovn-nbctl lsp-set-type sw1\$az-lr\$az router
ovn-nbctl lsp-set-addresses sw1\$az-lr\$az router
ovn-nbctl lsp-set-options sw1\$az-lr\$az router-port=lr\$az-sw1\$az

ovn-nbctl ls-add public\$az
ovn-nbctl lrp-add lr\$az lr\$az-public\$az 00:0\$az:20:20:12:13 172.16.\$az.100/24 300\$az::a/64
ovn-nbctl lsp-add public\$az public\$az-lr\$az
ovn-nbctl lsp-set-type public\$az-lr\$az router
ovn-nbctl lsp-set-addresses public\$az-lr\$az router
ovn-nbctl lsp-set-options public\$az-lr\$az router-port=lr\$az-public\$az

# localnet port
ovn-nbctl lsp-add public\$az ln-public\$az
ovn-nbctl lsp-set-type ln-public\$az localnet
ovn-nbctl lsp-set-addresses ln-public\$az unknown
ovn-nbctl lsp-set-options ln-public\$az network_name=public

# schedule the gw router port to a chassis.
ovn-nbctl lrp-set-gateway-chassis lr\$az-public\$az ovn-gw-\$az 20

# Create NAT entries for the ports

# sw0\$az-port1
ovn-nbctl lr-nat-add lr\$az dnat_and_snat 172.16.\$az.110 1\$az.0.0.3 sw0\$az-port1 30:5\$az:00:00:00:03
ovn-nbctl lr-nat-add lr\$az dnat_and_snat 300\$az::c 100\$az::3 sw0\$az-port1 40:5\$az:00:00:00:03
# sw1\$az-port1
ovn-nbctl lr-nat-add lr\$az dnat_and_snat 172.16.\$az.120 2\$az.0.0.3 sw1\$az-port1 30:5\$az:00:00:00:04
ovn-nbctl lr-nat-add lr\$az dnat_and_snat 300\$az::d 200\$az::3 sw1\$az-port1 40:5\$az:00:00:00:04

# Add a snat entry
ovn-nbctl lr-nat-add lr\$az snat 172.16.\$az.100 1\$az.0.0.0/24
ovn-nbctl lr-nat-add lr\$az snat 172.16.\$az.100 2\$az.0.0.0/24

if [ "\$ic" == "yes" ]; then
    ovn-nbctl lrp-add lr\$az lr\$az-ts1 aa:aa:aa:aa:aa:0\$az 5.0.0.\$az/24
    ovn-nbctl lsp-add ts1 ts1-lr\$az -- lsp-set-addresses ts1-lr\$az -- lsp-set-type ts1-lr\$az router -- lsp-set-options ts1-lr\$az  router-port=lr\$az-ts1
    ovn-nbctl lrp-set-gateway-chassis lr\$az-ts1 ovn-gw-\$az 1
fi

EOF
    chmod 0755 ${FAKENODE_MNT_DIR}/create_ovn_res.sh

    # add ts transit switch.
    ${RUNC_CMD} exec ${CENTRAL_IC_ID} ovn-ic-nbctl --may-exist ts-add ts1
    # wait for ovn-ic to kick in
    while sleep 2; do
        ${RUNC_CMD} exec ${CENTRAL_IC_ID} ovn-nbctl ls-list | grep -q ts1 && break
    done

    if [ "$OVN_DB_CLUSTER" = "yes" ]; then
        ${RUNC_CMD} exec ${CENTRAL_PREFIX}${az}-1 bash /data/create_ovn_res.sh $az $ic
    else
        ${RUNC_CMD} exec ${CENTRAL_PREFIX}${az} bash /data/create_ovn_res.sh $az $ic
    fi


    cat << EOF > ${FAKENODE_MNT_DIR}/create_fake_vm.sh
#!/bin/bash
create_fake_vm() {
    iface_id=\$1
    name=\$2
    mac=\$3
    mtu=\$4
    ip=\$5
    mask=\$6
    gw=\$7
    ipv6_addr=\$8
    ipv6_gw=\$9
    ip netns add \$name
    ip link add \$name-p type veth peer name \$name
    ip link set \$name netns \$name
    ip netns exec \$name ip link set lo up
    ip link set \$name-p up

    ovs-vsctl \
      -- add-port br-int \$name-p \
      -- set Interface \$name-p external_ids:iface-id=\$iface_id
    ip netns exec \$name ip link set lo up
    [ -n "\$mac" ] && ip netns exec \$name ip link set \$name address \$mac
    ip netns exec \$name ip link set \$name mtu \$mtu
    if [ "\$ip" == "dhcp" ]; then
      ip netns exec \$name ip link set \$name up
      #ip netns exec \$name dhclient -sf /bin/fullstack-dhclient-script --no-pid -1 -v --timeout 10 \$name
      ip netns exec \$name dhclient -sf /bin/fullstack-dhclient-script --no-pid -nw \$name
    else
      ip netns exec \$name ip addr add \$ip/\$mask dev \$name
      ip netns exec \$name ip addr add \$ipv6_addr dev \$name
      ip netns exec \$name ip link set \$name up
      ip netns exec \$name ip route add default via \$gw dev \$name
      ip netns exec \$name ip -6 route add default via \$ipv6_gw dev \$name
    fi
}

create_fake_vm \$@

EOF
    chmod 0755 ${FAKENODE_MNT_DIR}/create_fake_vm.sh

    echo "Creating a fake VM in "${CHASSIS_NAMES[$((az-1))]}" for logical port - sw0$az-port1"
    ${RUNC_CMD} exec "${CHASSIS_NAMES[$((az-1))]}" bash /data/create_fake_vm.sh sw0$az-port1 sw0${az}p1 50:5$az:00:00:00:03 1400 1$az.0.0.3 24 1$az.0.0.1 100$az::3/64 100$az::a
    echo "Creating a fake VM in "${CHASSIS_NAMES[$((az+CENTRAL_COUNT-1))]}" for logical port - sw1$az-port1"
    ${RUNC_CMD} exec "${CHASSIS_NAMES[$((az+CENTRAL_COUNT-1))]}" bash /data/create_fake_vm.sh sw1$az-port1 sw1${az}p1 40:5$az:00:00:00:03 1400 2$az.0.0.3 24 2$az.0.0.1 200$az::3/64 200$az::a

    echo "Creating a fake VM in "${CHASSIS_NAMES[$((az-1))]}" for logical port - sw0$az-port3 (using dhcp)"
    ${RUNC_CMD} exec "${CHASSIS_NAMES[$((az-1))]}" bash /data/create_fake_vm.sh sw0$az-port3 sw0${az}p3 50:5$az:00:00:00:05 1400 dhcp
    echo "Creating a fake VM in "${CHASSIS_NAMES[$((az+CENTRAL_COUNT-1))]}" for logical port - sw0$az-port4 (using dhcp)"
    ${RUNC_CMD} exec "${CHASSIS_NAMES[$((az+CENTRAL_COUNT-1))]}" bash /data/create_fake_vm.sh sw0$az-port4 sw0${az}p4 50:5$az:00:00:00:06 1400 dhcp

    echo "Creating a fake VM in the host bridge ${OVN_EXT_BR}"
    ip netns add ovnfake-ext$az
    ovs-vsctl add-port ${OVN_EXT_BR} ovnfake-ext$az -- set interface ovnfake-ext$az type=internal
    ip link set ovnfake-ext$az netns ovnfake-ext$az
    ip netns exec ovnfake-ext$az ip link set lo up
    ip netns exec ovnfake-ext$az ip link set ovnfake-ext$az address 30:5$az:00:00:00:50
    ip netns exec ovnfake-ext$az ip addr add 172.16.$az.50/24 dev ovnfake-ext$az
    ip netns exec ovnfake-ext$az ip addr add 300$az::b/64 dev ovnfake-ext$az
    ip netns exec ovnfake-ext$az ip link set ovnfake-ext$az up
    ip netns exec ovnfake-ext$az ip route add default via 172.16.$az.100

    echo "Creating a fake VM in the ovs bridge ${OVN_BR}"
    ip netns add ovnfake-int$az
    ovs-vsctl add-port ${OVN_BR} ovnfake-int$az -- set interface ovnfake-int$az type=internal
    ip link set ovnfake-int$az netns ovnfake-int$az
    ip netns exec ovnfake-int$az ip link set lo up
    ip netns exec ovnfake-int$az ip link set ovnfake-int$az address 30:5$az:00:00:00:60
    ip netns exec ovnfake-int$az ip addr add 170.168.0.1/${IP_CIDR} dev ovnfake-int$az
    ip netns exec ovnfake-int$az ip link set ovnfake-int$az up
}

function set-ovn-remote() {
    ovn_remote=$1
    ovn_central=$2
    ovn_central_name=$3

    if [ "x$ovn_central_name" == "x" ]; then
        ovn_central_name="ovn-central-az1"
    fi

    echo "OVN remote = $1"
    existing_chassis=$(count-chassis "${filter}")
    if (( existing_chassis == 0)); then
        echo
        echo "ERROR: First start ovn-fake-multinode"
        exit 1
    fi

    if [ "$OVN_DB_CLUSTER" != "yes" ] && [ "$ovn_central" == "yes" ]; then
        ${RUNC_CMD} exec $ovn_central_name ovs-vsctl set open . external_ids:ovn-remote=$ovn_remote
    fi

    for name in "${GW_NAMES[@]}"; do
        echo "Setting remote for $name"
        ${RUNC_CMD} exec ${name} ovs-vsctl set open . external_ids:ovn-remote=$ovn_remote
    done

    for name in "${CHASSIS_NAMES[@]}"; do
        echo "Setting remote for $name"
        ${RUNC_CMD} exec ${name} ovs-vsctl set open . external_ids:ovn-remote=$ovn_remote
    done
}

# This function only starts chassis containers (running ovn-controller)
function start-chassis() {
    ovn_central=no
    ovn_remote=$1
    ovn_add_chassis=$2
    start $ovn_central $ovn_remote $ovn_add_chassis
}

function os-image-pull() {
    cmd="${RUNC_CMD} pull ${OS_IMAGE}"
    retries=0
    until [ $retries -ge ${OS_IMAGE_PULL_RETRIES} ]
    do
        $cmd && return
        sleep ${OS_IMAGE_PULL_INTERVAL}
        ((retries++)) ||:
    done
    echo >&2 "retry failure limit reached"
    exit 1
}

function build-images() {
    # Copy dbus.service to a place where image build can see it
    cp -v /usr/lib/systemd/system/dbus.service . 2>/dev/null || touch dbus.service
    sed -i 's/OOMScoreAdjust=-900//' ./dbus.service 2>/dev/null || :

    os-image-pull
    ${RUNC_CMD} build -t ovn/cinc --build-arg OS_IMAGE=${OS_IMAGE} \
    --build-arg OS_BASE=${OS_BASE} -f image/cinc/Dockerfile .

    ${RUNC_CMD} build -t ovn/ovn-multi-node --build-arg OVS_SRC_PATH=ovs \
    --build-arg OVN_SRC_PATH=ovn --build-arg USE_OVN_RPMS=${USE_OVN_RPMS} \
    --build-arg USE_OVN_DEBS=${USE_OVN_DEBS} \
    --build-arg EXTRA_OPTIMIZE=${EXTRA_OPTIMIZE} \
    --build-arg INSTALL_UTILS_FROM_SOURCES=${INSTALL_UTILS_FROM_SOURCES} \
    --build-arg USE_OVSDB_ETCD=${USE_OVSDB_ETCD} \
    -f  image/ovn/Dockerfile .
}

function check-for-ovn-rpms() {
    USE_OVN_RPMS=yes
    ls ovn*.rpm > /dev/null 2>&1 || USE_OVN_RPMS=no
}

function check-for-ovn-debs() {
    USE_OVN_DEBS=yes
    ls ovn*.deb > /dev/null 2>&1 || USE_OVN_DEBS=no
}

function build-images-with-ovn-rpms() {
    mkdir -p ovs
    mkdir -p ovn
    rm -f tst.rpm
    build-images
}

function build-images-with-ovn-debs() {
    mkdir -p ovs
    mkdir -p ovn
    rm -f tst.deb
    build-images
}

function build-images-with-ovn-sources() {
    if [ ! -d ./ovs ]; then
	    echo "OVS_SRC_PATH = $OVS_SRC_PATH"
	    if [ "${OVS_SRC_PATH}" = "" ]; then
            echo "Set the OVS_SRC_PATH var pointing to the location of ovs source code."
            exit 1
	    fi

	    rm -rf ./ovs
	    cp -rf $OVS_SRC_PATH ./ovs
	    DO_RM_OVS='yes'
    fi

    if [ ! -d ./ovn ]; then
	    echo "OVN_SRC_PATH = $OVN_SRC_PATH"
	    if [ "${OVN_SRC_PATH}" = "" ]; then
            echo "Set the OVN_SRC_PATH var pointing to the location of ovn source code."
            exit 1
	    fi
	    rm -rf ovn
	    cp -rf $OVN_SRC_PATH ovn
	    DO_RM_OVN='yes'
    fi

    touch tst.rpm
    touch tst.deb
    build-images
    rm -f tst.rpm
    rm -f tst.deb
    [ -n "$DO_RM_OVS" ] && rm -rf ovs ||:
    [ -n "$DO_RM_OVN" ] && rm -rf ovn ||:
}

function run-command() {
    ovn_central_name=$1
    shift;
    cmd=$@

    echo "Running command $cmd in container $ovn_central_name"
    ${RUNC_CMD} exec $ovn_central_name $cmd ||:

    for name in "${GW_NAMES[@]}"; do
        echo "Running command $cmd in container $name"
        ${RUNC_CMD} exec $name $cmd ||:
    done

    for name in "${RELAY_NAMES[@]}"; do
        echo "Running command $cmd in container $name"
        ${RUNC_CMD} exec $name $cmd ||:
    done

    for name in "${CHASSIS_NAMES[@]}"; do
        echo "Running command $cmd in container $name"
        ${RUNC_CMD} exec $name $cmd ||:
    done
}

case "${1:-""}" in
    start)
        while getopts ":abc:in:rsN:lm:" opt; do
            BUILD=
            BUILD_IMAGES=
            WAIT_FOR_CLUSTER=1
            REMOVE_EXISTING_CLUSTER=
            ADDITIONAL_NETWORK_INTERFACE=
            case $opt in
            i)
                BUILD_IMAGES=1
                ;;
            C)
                CHASSIS_COUNT="${OPTARG}"
                ;;
            G)
                GW_COUNT="${OPTARG}"
                ;;
            r)
                REMOVE_EXISTING_CLUSTER=1
                ;;
            s)
                WAIT_FOR_CLUSTER=
                ;;
            c)
                CONTAINER_RUNTIME="${OPTARG}"
                ;;
            \?)
                echo "Invalid option: -${OPTARG}" >&2
                exit 1
            ;;
            :)
                echo "Option -${OPTARG} requires an argument." >&2
                exit 1
                ;;
            esac
        done

        if [ "${CREATE_FAKE_VMS}" == "yes" ]; then
            [ $CHASSIS_COUNT -lt $((2*CENTRAL_COUNT)) ] && CHASSIS_COUNT=$((2*CENTRAL_COUNT))
            [ $GW_COUNT -lt $CENTRAL_COUNT ] && GW_COUNT=$CENTRAL_COUNT
        fi

        set_node_names

        if [[ -n "${REMOVE_EXISTING_CLUSTER}" ]]; then
            stop
        fi

        start
        if [ "${CREATE_FAKE_VMS}" == "yes" ]; then
            for i in $(seq $CENTRAL_COUNT); do
                create_fake_vms $i $CENTRAL_COUNT
            done
        fi
        ;;
    start-chassis)
        for (( i=1; i<=CHASSIS_COUNT; i++ )); do
            CHASSIS_NAMES+=( "${CHASSIS_PREFIX}${i}" )
        done
        start-chassis $2 "no"
        ;;
    add-chassis)
        GW_COUNT=0
        CHASSIS_NAMES=( "$2" )
        start-chassis $3 "yes"
        ;;
    stop)
        set_node_names
        stop
        ;;
    stop-chassis)
        del-ovs-container-ports $2
        stop-container $2
        ;;
    build)
        check-for-ovn-rpms
        check-for-ovn-debs
        if [ "$USE_OVN_RPMS" == "yes" ] && [ "$USE_OVN_DEBS" == "yes" ] ; then
            echo "Do not keep rpm and deb packages on the same directory or enable both package manager!"
            exit 1
        fi 
        if [ "$USE_OVN_RPMS" == "yes" ] ; then
	    echo "Building images using OVN rpms"
            build-images-with-ovn-rpms
	elif [ "$USE_OVN_DEBS" == "yes" ] ; then
            echo "Building images using OVN debs"
            build-images-with-ovn-debs
        else
            echo "Building images using OVN/OVS sources"
            build-images-with-ovn-sources
        fi
        ;;
    set-ovn-remote)
        set_node_names
        set-ovn-remote $2 "yes" $3
        ;;
    set-chassis-ovn-remote)
        CHASSIS_NAMES=( "$2" )
        GW_NAMES=( )
        RELAY_NAMES=( )
        CHASSIS_PREFIX=$2
        set-ovn-remote $3 "no" $4
        ;;
    run-command)
        set_node_names
        shift;
        run-command $@
        ;;
    --version)
        ;&
    -v)
        v=$(cat $(dirname $0)/VERSION)
        echo "v$v"
    esac

exit 0
