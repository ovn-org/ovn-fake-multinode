#!/bin/bash -xe

export DEBIAN_FRONTEND=noninteractive

apt update
apt install -yq --no-install-recommends \
  autoconf \
  automake \
  conntrack \
  conntrackd \
  curl \
  isc-dhcp-client \
  file \
  fping \
  gcc \
  gettext \
  git \
  init \
  iproute2 \
  iptables \
  iputils-ping \
  libjs-d3 \
  libcap-dev \
  libreswan \
  libtool \
  libxslt1.1 \
  lksctp-tools \
  libsctp-dev \
  make \
  meson \
  net-tools \
  nmap \
  openssh-client \
  openssh-server \
  openssl \
  pkg-config \
  libssl-dev \
  procps \
  python3-dev \
  python3-pip \
  python3-psutil \
  python3-six \
  resource-agents \
  tcpdump \
  uuid

systemctl mask \
	auditd.service \
	console-getty.service \
	dev-hugepages.mount \
	getty.target \
	lvm2-lvmetad.service \
	sys-fs-fuse-connections.mount \
	systemd-logind.service \
	systemd-remount-fs.service \
	systemd-udev-hwdb-update.service \
	systemd-udevd.service \
	systemd-vconsole-setup.service


# Generate variation of dhclient-script that we can use for fake vm namespaces.
# dhclient-script might not be available though, so don't fail if that's
# the case.
mkdir -pv /bin
/tmp/generate_dhclient_script_for_fullstack.sh / || \
    echo "Failed to generate dhclient script for fullstack!"
