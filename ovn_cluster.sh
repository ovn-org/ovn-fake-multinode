#!/bin/bash

#set -o xtrace
set -o errexit

RUNC_CMD="${RUNC_CMD:-sudo docker}"

BASE_IMAGE="ovn/cinc"
CENTRAL_IMAGE="ovn/ovn-multi-node"
CHASSIS_IMAGE="ovn/ovn-multi-node"
GW_IMAGE="ovn/ovn-multi-node"

USE_OVN_RPMS="${USE_OVN_RPMS:-no}"

CENTRAL_NAME="ovn-central"
CHASSIS_PREFIX="${CHASSIS_PREFIX:-ovn-chassis-}"
GW_PREFIX="ovn-gw-"

CHASSIS_COUNT=${CHASSIS_COUNT:-2}
CHASSIS_NAMES=()

GW_COUNT=${GW_COUNT:-1}
GW_NAMES=()

OVN_BR="br-ovn"
OVN_EXT_BR="br-ovn-ext"
OVN_BR_CLEANUP="${OVN_BR_CLEANUP:-yes}"

OVS_DOCKER="./ovs-docker"

OVN_SRC_PATH="${OVN_SRC_PATH:-}"
OVS_SRC_PATH="${OVS_SRC_PATH:-}"

OVNCTL_PATH=/usr/share/ovn/scripts/ovn-ctl

IP_HOST=${IP_HOST:-170.168.0.0}
IP_CIDR=${IP_CIDR:-16}
IP_START=${IP_START:-170.168.0.2}

OVN_DB_CLUSTER="${OVN_DB_CLUSTER:-no}"

CREATE_FAKE_VMS="${CREATE_FAKE_VMS:-yes}"


function check-selinux() {
  if [[ "$(getenforce)" = "Enforcing" ]]; then
    >&2 echo "Error: This script is not compatible with SELinux enforcing mode."
    exit 1
  fi
}

function count-central() {
    local filter=${1:-}
    count-containers "${CENTRAL_NAME}" "${filter}"
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
  for cid in $( ${RUNC_CMD} ps -qa --filter "name=${name}" $filter); do
    (( count += 1 ))
  done

  echo "$count"
}

function check-no-containers {
  local operation=$1
  local filter=${2:-}
  local message="${3:-Existing cluster parts}"

  local existing_nodes existing_master
  existing_chassis=$(count-chassis "${filter}")
  existing_central=$(count-central "${filter}")
  existing_gws=$(count-gw "${filter}")
  if (( existing_chassis > 0 || existing_central > 0 || existing_gws > 0)); then
    echo
    echo "ERROR: Can't ${operation}.  ${message} (${existing_central} existing central or ${existing_chassis} existing chassis)"
    exit 1
  fi
}

function start-container() {
  local image=$1
  local name=$2

  local volumes run_cmd
  volumes=""

  ${RUNC_CMD} run  -dt ${volumes} -v "/tmp/ovn-multinode:/data" --privileged \
                --name="${name}" --hostname="${name}" "${image}" > /dev/null
}

function stop-container() {
    local cid=$1

    ${RUNC_CMD} rm -f "${cid}" > /dev/null
}

function stop() {
    ip netns delete ovnfake-ext || :
    if [ "${OVN_BR_CLEANUP}" == "yes" ]; then
        ovs-vsctl --if-exists del-br $OVN_BR || exit 1
        ovs-vsctl --if-exists del-br $OVN_EXT_BR || exit 1
    else
        del-ovs-docker-ports ${CENTRAL_NAME}
        for name in "${GW_NAMES[@]}"; do
            del-ovs-docker-ports ${name}
        done
        for name in "${CHASSIS_NAMES[@]}"; do
            del-ovs-docker-ports ${name}
        done
    fi

    echo "Stopping OVN cluster"
    # Delete the containers
    for cid in $( ${RUNC_CMD} ps -qa --filter "name=${CENTRAL_NAME}|${GW_PREFIX}|${CHASSIS_PREFIX}" ); do
       stop-container ${cid}
    done
}

function setup-ovs-in-host() {
    ovs-vsctl br-exists $OVN_BR || ovs-vsctl add-br $OVN_BR || exit 1
    ovs-vsctl br-exists $OVN_BR || ovs-vsctl add-br $OVN_EXT_BR || exit 1
}

function add-ovs-docker-ports() {
    ovn_central=$1
    ip_range=$IP_HOST
    cidr=$IP_CIDR
    ip_start=$IP_START

    br=br-ovn
    eth=eth1

    ip_index=0
    ip=$(./ip_gen.py $ip_range/$cidr $ip_start 0)
    if [ "$ovn_central" == "yes" ]; then
        if [ "$OVN_DB_CLUSTER" = "yes" ]; then
            ip1=$ip
            ${OVS_DOCKER} add-port $br $eth ${CENTRAL_NAME}-1 --ipaddress=${ip1}/${cidr}

            (( ip_index += 1))
            ip2=$(./ip_gen.py $ip_range/$cidr $ip_start $ip_index)
            ${OVS_DOCKER} add-port $br $eth ${CENTRAL_NAME}-2 --ipaddress=${ip2}/${cidr}

            (( ip_index += 1))
            ip3=$(./ip_gen.py $ip_range/$cidr $ip_start $ip_index)
            ${OVS_DOCKER} add-port $br $eth ${CENTRAL_NAME}-3 --ipaddress=${ip3}/${cidr}
            echo "tcp:$ip1:6642,tcp:$ip2:6642:tcp:$ip3:6642" > _ovn_remote
        else
            ${OVS_DOCKER} add-port $br $eth ${CENTRAL_NAME} --ipaddress=${ip}/${cidr}
            echo "tcp:$ip:6642" > _ovn_remote
        fi

        for name in "${GW_NAMES[@]}"; do
            (( ip_index += 1))
            ip=$(./ip_gen.py $ip_range/$cidr $ip_start $ip_index)
            ${OVS_DOCKER} add-port $br $eth ${name} --ipaddress=${ip}/${cidr}
        done
    fi

    for name in "${CHASSIS_NAMES[@]}"; do
        (( ip_index += 1))
        ip=$(./ip_gen.py $ip_range/$cidr $ip_start $ip_index)
        ${OVS_DOCKER} add-port $br $eth ${name} --ipaddress=${ip}/${cidr}
    done

    if [ "$ovn_central" == "yes" ]; then
        if [ "$OVN_DB_CLUSTER" = "yes" ]; then
            ${OVS_DOCKER} add-port br-ovn-ext eth2 ${CENTRAL_NAME}-1
            ${OVS_DOCKER} add-port br-ovn-ext eth2 ${CENTRAL_NAME}-2
            ${OVS_DOCKER} add-port br-ovn-ext eth2 ${CENTRAL_NAME}-3
        else
            ${OVS_DOCKER} add-port br-ovn-ext eth2 ${CENTRAL_NAME}
        fi
        for name in "${GW_NAMES[@]}"; do
            ${OVS_DOCKER} add-port br-ovn-ext eth2 ${name}
        done
    fi

    for name in "${CHASSIS_NAMES[@]}"; do
        ${OVS_DOCKER} add-port br-ovn-ext eth2 ${name}
    done
}

function del-ovs-docker-ports() {
    local name=$1

    ${OVS_DOCKER} del-port $OVN_BR eth1 ${name} || :
    ${OVS_DOCKER} del-port $OVN_EXT_BR eth2 ${name} || :
}

function configure-ovn() {
    ovn_central=$1
    ovn_remote=$2

    rm -f /tmp/ovn-multinode/configure_ovn.sh

    cat << EOF > /tmp/ovn-multinode/configure_ovn.sh
#!/bin/bash

eth=\$1
ovn_remote=\$2

if [ "\$eth" = "" ]; then
    eth=eth1
fi

ovn_remote=\$2

if [ "\$ovn_remote" = "" ]; then
    ovn_remote="tcp:170.168.0.2:6642"
fi

ip=\`ip addr show \$eth | grep inet | grep -v inet6 | awk '{print \$2}' | cut -d'/' -f1\`

ovs-vsctl set open . external_ids:ovn-encap-ip=\$ip
ovs-vsctl set open . external-ids:ovn-encap-type=geneve
ovs-vsctl set open . external-ids:ovn-remote=\$ovn_remote
ovs-vsctl set open . external-ids:ovn-openflow-probe-interval=60
ovs-vsctl set open . external-ids:ovn-remote-probe-interval=180000

ovs-vsctl --if-exists del-br br-ex
ovs-vsctl add-br br-ex
ovs-vsctl set open . external-ids:ovn-bridge-mappings=public:br-ex

ip link set eth2 down
ovs-vsctl add-port br-ex eth2
ip link set eth2 up
EOF

    chmod 0755 /tmp/ovn-multinode/configure_ovn.sh

    if [ "$ovn_central" == "yes" ]; then
        if [ "$OVN_DB_CLUSTER" != "yes" ]; then
            ${RUNC_CMD} exec ${CENTRAL_NAME} bash /data/configure_ovn.sh eth1 $ovn_remote
        fi

        for name in "${GW_NAMES[@]}"; do
            ${RUNC_CMD} exec ${name} bash /data/configure_ovn.sh eth1 $ovn_remote
        done
    fi
    for name in "${CHASSIS_NAMES[@]}"; do
        ${RUNC_CMD} exec ${name} bash /data/configure_ovn.sh eth1 $ovn_remote
    done
}

function wait-containers() {
    local ovn_central=$1
    echo "Waiting for containers to be up.."
    while : ; do
        local done="1"
        if [ "${ovn_central}" == "yes" ]; then
            if [ "$OVN_DB_CLUSTER" = "yes" ]; then
                [[ $(count-containers "${CENTRAL_NAME}-1") == "0" ]] && continue
                [[ $(count-containers "${CENTRAL_NAME}-2") == "0" ]] && continue
                [[ $(count-containers "${CENTRAL_NAME}-3") == "0" ]] && continue
            else
                [[ $(count-containers "${CENTRAL_NAME}") == "0" ]] && continue
            fi
            for name in "${GW_NAMES[@]}"; do
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

# Starts OVN dbs RAFT cluster on ovn-central-1, ovn-central-2 and ovn-central-3
# containers.
function start-db-cluster() {
    ${RUNC_CMD} exec ${CENTRAL_NAME}-1 ${OVNCTL_PATH} --db-nb-addr=170.168.0.2 --db-nb-create-insecure-remote=yes  \
--db-sb-addr=170.168.0.2 --db-sb-create-insecure-remote=yes --db-nb-cluster-local-addr=170.168.0.2 \
--db-sb-cluster-local-addr=170.168.0.2 start_ovsdb

    ${RUNC_CMD} exec ${CENTRAL_NAME}-2 ${OVNCTL_PATH} --db-nb-addr=170.168.0.3 --db-nb-create-insecure-remote=yes  \
--db-sb-addr=170.168.0.3 --db-sb-create-insecure-remote=yes \
--db-nb-cluster-local-addr=170.168.0.3 --db-nb-cluster-remote-addr=170.168.0.2 \
--db-sb-cluster-local-addr=170.168.0.3 --db-sb-cluster-remote-addr=170.168.0.2 start_ovsdb

    ${RUNC_CMD} exec ${CENTRAL_NAME}-3 ${OVNCTL_PATH} --db-nb-addr=170.168.0.4 --db-nb-create-insecure-remote=yes  \
--db-sb-addr=170.168.0.4 --db-sb-create-insecure-remote=yes \
--db-nb-cluster-local-addr=170.168.0.4 --db-nb-cluster-remote-addr=170.168.0.2 \
--db-sb-cluster-local-addr=170.168.0.4 --db-sb-cluster-remote-addr=170.168.0.2 start_ovsdb

    # This can be improved.
    sleep 3

    # Start ovn-northd only on ovn-central-1
    ${RUNC_CMD} exec ${CENTRAL_NAME}-1 ${OVNCTL_PATH}  --ovn-northd-nb-db=tcp:170.168.0.2:6641,tcp:170.168.0.3:6641,tcp:170.168.0.4:6641 \
--ovn-northd-sb-db=tcp:170.168.0.2:6642,tcp:170.168.0.3:6642,tcp:170.168.0.4:6642 --ovn-manage-ovsdb=no start_northd

    ${RUNC_CMD} exec ${CENTRAL_NAME}-1 ovn-nbctl set-connection ptcp:6641
    ${RUNC_CMD} exec ${CENTRAL_NAME}-1 ovn-sbctl set-connection ptcp:6642
    ${RUNC_CMD} exec ${CENTRAL_NAME}-1 ovn-sbctl set connection . inactivity_probe=180000
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

    if [ "$ovn_add_chassis" == "no" ]; then
        check-no-containers "start"
    fi

    # docker-in-docker's use of volumes is not compatible with SELinux
    #check-selinux

    setup-ovs-in-host

    mkdir -p /tmp/ovn-multinode

    # Create containers
    if [ "$ovn_central" == "yes" ]; then
        if [ "$OVN_DB_CLUSTER" = "yes" ]; then
            start-container "${CENTRAL_IMAGE}" "${CENTRAL_NAME}-1"
            start-container "${CENTRAL_IMAGE}" "${CENTRAL_NAME}-2"
            start-container "${CENTRAL_IMAGE}" "${CENTRAL_NAME}-3"
        else
            start-container "${CENTRAL_IMAGE}" "${CENTRAL_NAME}"
        fi

        for name in "${GW_NAMES[@]}"; do
            start-container "${GW_IMAGE}" "${name}"
        done
    fi

    for name in "${CHASSIS_NAMES[@]}"; do
        start-container "${CHASSIS_IMAGE}" "${name}"
    done

    wait-containers ${ovn_central}

    echo "Adding ovs-ports"
    # Add ovs ports to each of the nodes.
    add-ovs-docker-ports $ovn_central

    if [ "$ovn_remote" == "" ]; then
        if [ -e _ovn_remote ]; then
            ovn_remote="$(cat _ovn_remote)"
        fi
    fi

    # Start OVN db servers on central node
    if [ "$ovn_central" == "yes" ]; then
        if [ "$OVN_DB_CLUSTER" = "yes" ]; then
            start-db-cluster
        else
            ${RUNC_CMD} exec ${CENTRAL_NAME} ${OVNCTL_PATH} start_northd
            sleep 2
            ${RUNC_CMD} exec ${CENTRAL_NAME} ovn-nbctl set-connection ptcp:6641
            ${RUNC_CMD} exec ${CENTRAL_NAME} ovn-sbctl set-connection ptcp:6642
            ${RUNC_CMD} exec ${CENTRAL_NAME} ovn-sbctl set connection . inactivity_probe=180000

            # Start openvswitch and ovn-controller on each node
            ${RUNC_CMD} exec ${CENTRAL_NAME} /usr/share/openvswitch/scripts/ovs-ctl start --system-id=${CENTRAL_NAME}
            ${RUNC_CMD} exec ${CENTRAL_NAME} ${OVNCTL_PATH} start_controller
        fi

        for name in "${GW_NAMES[@]}"; do
            ${RUNC_CMD} exec ${name} /usr/share/openvswitch/scripts/ovs-ctl start --system-id=${name}
            ${RUNC_CMD} exec ${name} ${OVNCTL_PATH} start_controller
        done
    fi

    for name in "${CHASSIS_NAMES[@]}"; do
        ${RUNC_CMD} exec ${name} /usr/share/openvswitch/scripts/ovs-ctl start --system-id=${name}
        ${RUNC_CMD} exec ${name} ${OVNCTL_PATH} start_controller
    done

    configure-ovn $ovn_central $ovn_remote
}

function create_fake_vms() {
    cat << EOF > /tmp/ovn-multinode/create_ovn_res.sh
#!/bin/bash

#set -o xtrace
set -o errexit

ovn-nbctl ls-add sw0

# ovn dhcpd on sw0
ovn-nbctl set logical_switch sw0 \
  other_config:subnet="10.0.0.0/24" \
  other_config:exclude_ips="10.0.0.1..10.0.0.2"
ovn-nbctl dhcp-options-create 10.0.0.0/24
CIDR_UUID=\$(ovn-nbctl --bare --columns=_uuid find dhcp_options cidr="10.0.0.0/24")
ovn-nbctl dhcp-options-set-options \$CIDR_UUID \
  lease_time=3600 \
  router=10.0.0.1 \
  server_id=10.0.0.1 \
  server_mac=c0:ff:ee:00:00:01

ovn-nbctl lsp-add sw0 sw0-port1
ovn-nbctl lsp-set-addresses sw0-port1 "50:54:00:00:00:03 10.0.0.3"
ovn-nbctl lsp-add sw0 sw0-port2
ovn-nbctl lsp-set-addresses sw0-port2 "50:54:00:00:00:04 10.0.0.4"

# Create ports in sw0 that will use dhcp from ovn
ovn-nbctl lsp-add sw0 sw0-port3
ovn-nbctl lsp-set-addresses sw0-port3 "50:54:00:00:00:05 dynamic"
ovn-nbctl lsp-set-dhcpv4-options sw0-port3 \$CIDR_UUID
ovn-nbctl lsp-add sw0 sw0-port4
ovn-nbctl lsp-set-addresses sw0-port4 "50:54:00:00:00:06 dynamic"
ovn-nbctl lsp-set-dhcpv4-options sw0-port4 \$CIDR_UUID

# Create the second logical switch with one port
ovn-nbctl ls-add sw1
ovn-nbctl lsp-add sw1 sw1-port1
ovn-nbctl lsp-set-addresses sw1-port1 "40:54:00:00:00:03 20.0.0.3"

# Create a logical router and attach both logical switches
ovn-nbctl lr-add lr0
ovn-nbctl lrp-add lr0 lr0-sw0 00:00:00:00:ff:01 10.0.0.1/24
ovn-nbctl lsp-add sw0 sw0-lr0
ovn-nbctl lsp-set-type sw0-lr0 router
ovn-nbctl lsp-set-addresses sw0-lr0 router
ovn-nbctl lsp-set-options sw0-lr0 router-port=lr0-sw0

ovn-nbctl lrp-add lr0 lr0-sw1 00:00:00:00:ff:02 20.0.0.1/24
ovn-nbctl lsp-add sw1 sw1-lr0
ovn-nbctl lsp-set-type sw1-lr0 router
ovn-nbctl lsp-set-addresses sw1-lr0 router
ovn-nbctl lsp-set-options sw1-lr0 router-port=lr0-sw1

ovn-nbctl ls-add public
ovn-nbctl lrp-add lr0 lr0-public 00:00:20:20:12:13 172.16.0.100/24
ovn-nbctl lsp-add public public-lr0
ovn-nbctl lsp-set-type public-lr0 router
ovn-nbctl lsp-set-addresses public-lr0 router
ovn-nbctl lsp-set-options public-lr0 router-port=lr0-public

# localnet port
ovn-nbctl lsp-add public ln-public
ovn-nbctl lsp-set-type ln-public localnet
ovn-nbctl lsp-set-addresses ln-public unknown
ovn-nbctl lsp-set-options ln-public network_name=public

# schedule the gw router port to a chassis.
ovn-nbctl lrp-set-gateway-chassis lr0-public ovn-gw-1 20

# Create NAT entries for the ports

# sw0-port1
ovn-nbctl lr-nat-add lr0 dnat_and_snat 172.16.0.110 10.0.0.3 sw0-port1 30:54:00:00:00:03
ovn-nbctl lr-nat-add lr0 dnat_and_snat 172.16.0.120 20.0.0.3 sw1-port1 30:54:00:00:00:04

# Add a snat entry
ovn-nbctl lr-nat-add lr0 snat 172.16.0.100 10.0.0.0/24
ovn-nbctl lr-nat-add lr0 snat 172.16.0.100 20.0.0.0/24

EOF
    chmod 0755 /tmp/ovn-multinode/create_ovn_res.sh
    if [ "$OVN_DB_CLUSTER" = "yes" ]; then
        central=${CENTRAL_NAME}-1
    else
        central=${CENTRAL_NAME}
    fi
    ${RUNC_CMD} exec ${central} bash /data/create_ovn_res.sh

    cat << EOF > /tmp/ovn-multinode/create_fake_vm_static_ip.sh
#!/bin/bash
create_fake_vm() {
    name=\$1
    mac=\$2
    ip=\$3
    mask=\$4
    gw=\$5
    iface_id=\$6
    ip netns add \$name
    ovs-vsctl add-port br-int \$name -- set interface \$name type=internal
    ip link set \$name netns \$name
    ip netns exec \$name ip link set lo up
    ip netns exec \$name ip link set \$name address \$mac
    ip netns exec \$name ip addr add \$ip/\$mask dev \$name
    ip netns exec \$name ip link set \$name up
    ip netns exec \$name ip route add default via \$gw
    ovs-vsctl set Interface \$name external_ids:iface-id=\$iface_id
}

create_fake_vm \$@

EOF
    chmod 0755 /tmp/ovn-multinode/create_fake_vm_static_ip.sh

    cat << EOF > /tmp/ovn-multinode/create_fake_vm.sh
#!/bin/bash
create_fake_vm() {
    name=\$1
    mac=\$2
    iface_id=\$3
    ip netns add \$name
    ovs-vsctl add-port br-int \$name -- set interface \$name type=internal
    ip link set \$name netns \$name
    ip netns exec \$name ip link set lo up
    ip netns exec \$name ip link set \$name address \$mac
    ip netns exec \$name ip link set \$name up
    ovs-vsctl set Interface \$name external_ids:iface-id=\$iface_id

    #ip netns exec \$name dhclient -sf /bin/fullstack-dhclient-script --no-pid -1 -v --timeout 10 \$name
    ip netns exec \$name dhclient -sf /bin/fullstack-dhclient-script --no-pid -nw \$name
}

create_fake_vm \$@

EOF
    chmod 0755 /tmp/ovn-multinode/create_fake_vm.sh

    echo "Creating a fake VM in "${CHASSIS_NAMES[0]}" for logical port - sw0-port1"
    ${RUNC_CMD} exec "${CHASSIS_NAMES[0]}" bash /data/create_fake_vm_static_ip.sh sw0p1 50:54:00:00:00:03 10.0.0.3 24 10.0.0.1 sw0-port1
    echo "Creating a fake VM in "${CHASSIS_NAMES[1]}" for logical port - sw1-port1"
    ${RUNC_CMD} exec "${CHASSIS_NAMES[1]}" bash /data/create_fake_vm_static_ip.sh sw1p1 40:54:00:00:00:03 20.0.0.3 24 20.0.0.1 sw1-port1

    echo "Creating a fake VM in "${CHASSIS_NAMES[0]}" for logical port - sw0-port3 (using dhcp)"
    ${RUNC_CMD} exec "${CHASSIS_NAMES[0]}" bash /data/create_fake_vm.sh sw0p3 50:54:00:00:00:05 sw0-port3
    echo "Creating a fake VM in "${CHASSIS_NAMES[1]}" for logical port - sw0-port4 (using dhcp)"
    ${RUNC_CMD} exec "${CHASSIS_NAMES[1]}" bash /data/create_fake_vm.sh sw0p4 50:54:00:00:00:06 sw0-port4

    echo "Creating a fake VM in the host bridge br-ovn-ext"
    ip netns add ovnfake-ext
    ovs-vsctl add-port br-ovn-ext ovnfake-ext -- set interface ovnfake-ext type=internal
    ip link set ovnfake-ext netns ovnfake-ext
    ip netns exec ovnfake-ext ip link set lo up
    ip netns exec ovnfake-ext ip link set ovnfake-ext address 30:54:00:00:00:50
    ip netns exec ovnfake-ext ip addr add 172.16.0.50/24 dev ovnfake-ext
    ip netns exec ovnfake-ext ip link set ovnfake-ext up
    ip netns exec ovnfake-ext ip route add default via 172.16.0.1
}

function set-ovn-remote() {
    ovn_remote=$1
    ovn_central=$2
    echo "OVN remote = $1"
    existing_chassis=$(count-chassis "${filter}")
    if (( existing_chassis == 0)); then
        echo
        echo "ERROR: First start ovn-fake-multinode"
        exit 1
    fi

    if [ "$OVN_DB_CLUSTER" != "yes" ] && [ "$ovn_central" == "yes" ]; then
        ${RUNC_CMD} exec ${CENTRAL_NAME} ovs-vsctl set open . external_ids:ovn-remote=$ovn_remote
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

function build-images() {
    # Copy dbus.service to a place where image build can see it
    cp -v /usr/lib/systemd/system/dbus.service . 2>/dev/null || touch dbus.service
    sed -i 's/OOMScoreAdjust=-900//' ./dbus.service 2>/dev/null || :
    ${RUNC_CMD} build -t ovn/cinc -f fedora/cinc/Dockerfile .

    ${RUNC_CMD} build -t ovn/ovn-multi-node --build-arg OVS_SRC_PATH=ovs \
    --build-arg OVN_SRC_PATH=ovn --build-arg USE_OVN_RPMS=$USE_OVN_RPMS -f  fedora/ovn/Dockerfile .
}

function check-for-ovn-rpms() {
    USE_OVN_RPMS=yes
    ls ovn*.rpm || USE_OVN_RPMS=no
}

function build-images-with-ovn-rpms() {
    mkdir -p ovs
    mkdir -p ovn
    rm -f tst.rpm
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
    build-images
    rm -f tst.rpm
    [ -n "$DO_RM_OVS" ] && rm -rf ovs ||:
    [ -n "$DO_RM_OVN" ] && rm -rf ovn ||:
}

function run-command() {
    cmd=$@

    echo "Running command $cmd in container $CENTRAL_NAME"
    ${RUNC_CMD} exec $CENTRAL_NAME $cmd ||:

    for name in "${GW_NAMES[@]}"; do
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

        for (( i=1; i<=CHASSIS_COUNT; i++ )); do
            CHASSIS_NAMES+=( "${CHASSIS_PREFIX}${i}" )
        done

        for (( i=1; i<=GW_COUNT; i++ )); do
            GW_NAMES+=( "${GW_PREFIX}${i}" )
        done

        if [[ -n "${REMOVE_EXISTING_CLUSTER}" ]]; then
            stop
        fi

        start
        if [ "${CREATE_FAKE_VMS}" == "yes" ]; then
            create_fake_vms
        fi
        ;;
    start-chassis)
        for (( i=1; i<=CHASSIS_COUNT; i++ )); do
            CHASSIS_NAMES+=( "${CHASSIS_PREFIX}${i}" )
        done
        start-chassis $2 "no"
        ;;
    add-chassis)
        CHASSIS_NAMES=( "$2" )
        start-chassis $3 "yes"
        ;;
    stop)
        for (( i=1; i<=CHASSIS_COUNT; i++ )); do
            CHASSIS_NAMES+=( "${CHASSIS_PREFIX}${i}" )
        done

        for (( i=1; i<=GW_COUNT; i++ )); do
            GW_NAMES+=( "${GW_PREFIX}${i}" )
        done
        stop
        ;;
    stop-chassis)
        del-ovs-docker-ports $2
        stop-container $2
        ;;
    build)
        check-for-ovn-rpms
        if [ "$USE_OVN_RPMS" == "yes" ]
        then
            echo "Building images using OVN rpms"
            build-images-with-ovn-rpms
        else
            echo "Building images using OVN/OVS sources"
            build-images-with-ovn-sources
        fi
        ;;
    set-ovn-remote)
        for (( i=1; i<=CHASSIS_COUNT; i++ )); do
            CHASSIS_NAMES+=( "${CHASSIS_PREFIX}${i}" )
        done

        for (( i=1; i<=GW_COUNT; i++ )); do
            GW_NAMES+=( "${GW_PREFIX}${i}" )
        done

        set-ovn-remote $2 "yes"
        ;;
    set-chassis-ovn-remote)
        CHASSIS_NAMES=( "$2" )
        GW_NAMES=( )
        CHASSIS_PREFIX=$2
        set-ovn-remote $3 "no"
        ;;
    run-command)
        for (( i=1; i<=CHASSIS_COUNT; i++ )); do
            CHASSIS_NAMES+=( "${CHASSIS_PREFIX}${i}" )
        done

        for (( i=1; i<=GW_COUNT; i++ )); do
            GW_NAMES+=( "${GW_PREFIX}${i}" )
        done

        shift;
        run-command $@
    esac

exit 0
