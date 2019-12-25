#!/bin/bash

#set -o xtrace
set -o errexit

RUNC_CMD="${RUNC_CMD:-sudo podman}"

BASE_IMAGE="ovn/cinc"
CENTRAL_IMAGE="ovn/ovn-multi-node"
CHASSIS_IMAGE="ovn/ovn-multi-node"
GW_IMAGE="ovn/ovn-multi-node"

CENTRAL_NAME="ovn-central"
CHASSIS_PREFIX="ovn-chassis-"
GW_PREFIX="ovn-gw-"

CHASSIS_COUNT=2
CHASSIS_NAMES=()

GW_COUNT=1
GW_NAMES=()

OVN_BR="br-ovn"
OVN_EXT_BR="br-ovn-ext"

OVS_DOCKER="./ovs-docker"

OVN_SRC_PATH="${OVN_SRC_PATH:-}"
OVS_SRC_PATH="${OVS_SRC_PATH:-}"

OVNCTL_PATH=/usr/share/ovn/scripts/ovn-ctl

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

  ${RUNC_CMD} run --network none -dt ${volumes} -v "/tmp/ovn-multinode:/data" --privileged \
                --name="${name}" --hostname="${name}" "${image}" > /dev/null
}

function stop() {
    echo "Stopping OVN cluster"
    # Delete the containers
    for cid in $( ${RUNC_CMD} ps -qa --filter "name=${CENTRAL_NAME}|${GW_PREFIX}|${CHASSIS_PREFIX}" ); do
       ${RUNC_CMD} rm -f "${cid}" > /dev/null
    done

    ip netns delete ovnfake-ext || :
    ovs-vsctl --if-exists del-br $OVN_BR || exit 1
    ovs-vsctl --if-exists del-br $OVN_EXT_BR || exit 1
}

function setup-ovs-in-host() {
    ovs-vsctl br-exists $OVN_BR || ovs-vsctl add-br $OVN_BR || exit 1
    ovs-vsctl br-exists $OVN_BR || ovs-vsctl add-br $OVN_EXT_BR || exit 1
}

function add-ovs-docker-ports() {
    ovn_central=$1
    ip_range="170.168.0.0"
    cidr="24"
    ip_start="170.168.0.2"
    br=br-ovn
    eth=eth1

    ip_index=0
    ip=$(./ip_gen.py $ip_range/$cidr $ip_start 0)

    if [ "$ovn_central" == "yes" ]; then
        ${OVS_DOCKER} add-port $br $eth ${CENTRAL_NAME} --ipaddress=${ip}/${cidr}

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
        ${OVS_DOCKER} add-port br-ovn-ext eth2 ${CENTRAL_NAME}

        for name in "${GW_NAMES[@]}"; do
            ${OVS_DOCKER} add-port br-ovn-ext eth2 ${name}
        done
    fi

    for name in "${CHASSIS_NAMES[@]}"; do
        ${OVS_DOCKER} add-port br-ovn-ext eth2 ${name}
    done
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

ovs-vsctl --if-exists del-br br-ex
ovs-vsctl add-br br-ex
ovs-vsctl set open . external-ids:ovn-bridge-mappings=public:br-ex

ip link set eth2 down
ovs-vsctl add-port br-ex eth2
ip link set eth2 up
EOF

    chmod 0755 /tmp/ovn-multinode/configure_ovn.sh

    if [ "$ovn_central" == "yes" ]; then
        ${RUNC_CMD} exec ${CENTRAL_NAME} bash /data/configure_ovn.sh eth1 $ovn_remote

        for name in "${GW_NAMES[@]}"; do
            ${RUNC_CMD} exec ${name} bash /data/configure_ovn.sh eth1 $ovn_remote
        done
    fi
    for name in "${CHASSIS_NAMES[@]}"; do
        ${RUNC_CMD} exec ${name} bash /data/configure_ovn.sh eth1 $ovn_remote
    done
}

function start() {
    echo "Starting OVN cluster"
    ovn_central=$1
    ovn_remote=$2

    if [ "x$ovn_central" == "x" ]; then
        ovn_central="yes"
    fi

    # Check that no ovn related containers are running.
    check-no-containers "start"

    # docker-in-docker's use of volumes is not compatible with SELinux
    #check-selinux

    setup-ovs-in-host

    mkdir -p /tmp/ovn-multinode

    # Create containers
    if [ "$ovn_central" == "yes" ]; then
        start-container "${CENTRAL_IMAGE}" "${CENTRAL_NAME}"
        for name in "${GW_NAMES[@]}"; do
            start-container "${GW_IMAGE}" "${name}"
        done
    fi

    for name in "${CHASSIS_NAMES[@]}"; do
        start-container "${CHASSIS_IMAGE}" "${name}"
    done

    echo "Sleeping for 2 seconds"
    sleep 2

    echo "Adding ovs-ports"
    # Add ovs ports to each of the nodes.
    add-ovs-docker-ports $ovn_central

    # Start OVN db servers on central node
    if [ "$ovn_central" == "yes" ]; then
        ${RUNC_CMD} exec ${CENTRAL_NAME} ${OVNCTL_PATH} start_northd
        sleep 2
        ${RUNC_CMD} exec ${CENTRAL_NAME} ovn-nbctl set-connection ptcp:6641
        ${RUNC_CMD} exec ${CENTRAL_NAME} ovn-sbctl set-connection ptcp:6642

        # Start openvswitch and ovn-controller on each node
        ${RUNC_CMD} exec ${CENTRAL_NAME} /usr/share/openvswitch/scripts/ovs-ctl start --system-id=${CENTRAL_NAME}
        ${RUNC_CMD} exec ${CENTRAL_NAME} ${OVNCTL_PATH} start_controller

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

ovn-nbctl ls-add sw0
ovn-nbctl lsp-add sw0 sw0-port1
ovn-nbctl lsp-set-addresses sw0-port1 "50:54:00:00:00:03 10.0.0.3"

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
    ${RUNC_CMD} exec ${CENTRAL_NAME} bash /data/create_ovn_res.sh

    cat << EOF > /tmp/ovn-multinode/create_fake_vm.sh
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

    chmod 0755 /tmp/ovn-multinode/create_fake_vm.sh
    echo "Creating a fake VM in ovn-chassis-1 for logical port - sw0-port1"
    ${RUNC_CMD} exec ovn-chassis-1 bash /data/create_fake_vm.sh sw0p1 50:54:00:00:00:03 10.0.0.3 24 10.0.0.1 sw0-port1
    echo "Creating a fake VM in ovn-chassis-2 for logical port - sw1-port1"
    ${RUNC_CMD} exec ovn-chassis-2 bash /data/create_fake_vm.sh sw1p1 40:54:00:00:00:03 20.0.0.3 24 20.0.0.1 sw1-port1

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
    echo "OVN remote = $1"
    existing_chassis=$(count-chassis "${filter}")
    if (( existing_chassis == 0)); then
        echo
        echo "ERROR: First start ovn-fake-multinode"
        exit 1
    fi

    ${RUNC_CMD} exec ${CENTRAL_NAME} ovs-vsctl set open . external_ids:ovn-remote=$ovn_remote

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
    start $ovn_central $ovn_remote
}

function build-images() {
    rpm_present="yes"
    ls *.rpm > /dev/null || rpm_present="no"
    if [ "$rpm_present" == "yes" ]; then
        from_src=no
        rm -rf ovn
        rm -rf ovs
        mkdir ovn
        mkdir ovs
    else
        from_src="yes"
        touch tst.rpm
    fi

    if [ ! -d ./ovs ]; then
	echo "OVN_SRC_PATH = $OVN_SRC_PATH"
	if [ "${OVN_SRC_PATH}" = "" ]; then
            echo "Set the OVN_SRC_PATH var pointing to the location of ovn source code."
            exit 1
	fi
	rm -rf ./ovs
	cp -rf $OVS_SRC_PATH ./ovs
	DO_RM_OVS='yes'
    fi

    if [ ! -d ./ovn ]; then
	echo "OVS_SRC_PATH = $OVS_SRC_PATH"
	if [ "${OVS_SRC_PATH}" = "" ]; then
            echo "Set the OVS_SRC_PATH var pointing to the location of ovs source code."
            exit 1
	fi
	rm -rf ovn
	cp -rf $OVN_SRC_PATH ovn
	DO_RM_OVN='yes'
    fi

    # Copy dbus.service to a place where image build can see it
    cp -v /usr/lib/systemd/system/dbus.service . 2>/dev/null || touch dbus.service
    sed -i 's/OOMScoreAdjust=-900//' ./dbus.service 2>/dev/null || :
    ${RUNC_CMD} build -t ovn/cinc -f Dockerfile .

    ${RUNC_CMD} build -t ovn/ovn-multi-node --build-arg OVS_SRC_PATH=ovs --build-arg OVN_SRC_PATH=ovn -f fedora/Dockerfile .
    [ -n "$DO_RM_OVS" ] && rm -rf ovs ||:
    [ -n "$DO_RM_OVN" ] && rm -rf ovn ||:

    if [ "$rpm_present" == "no" ]; then
        rm -f tst.rpm
    fi
}

case "${1:-""}" in
    start)
        while getopts ":abc:in:rsN:lm:" opt; do
            BUILD=
            BUILD_IMAGES=
            WAIT_FOR_CLUSTER=1
            REMOVE_EXISTING_CULSTER=
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
        create_fake_vms
        ;;
    start-chassis)
        for (( i=1; i<=CHASSIS_COUNT; i++ )); do
            CHASSIS_NAMES+=( "${CHASSIS_PREFIX}${i}" )
        done
        start-chassis $2
        ;;
    stop)
        stop;;
    build)
        echo "Building images"
        build-images
        ;;
    set-ovn-remote)
        for (( i=1; i<=CHASSIS_COUNT; i++ )); do
            CHASSIS_NAMES+=( "${CHASSIS_PREFIX}${i}" )
        done

        for (( i=1; i<=GW_COUNT; i++ )); do
            GW_NAMES+=( "${GW_PREFIX}${i}" )
        done

        set-ovn-remote $2
        ;;
    esac

exit 0
