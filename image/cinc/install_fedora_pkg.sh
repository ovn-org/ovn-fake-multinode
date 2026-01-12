#!/bin/bash -xe

dnf -y install systemd

systemctl mask \
	auditd.service \
	console-getty.service \
	dev-hugepages.mount \
	dnf-makecache.service \
	getty.target \
	lvm2-lvmetad.service \
	sys-fs-fuse-connections.mount \
	systemd-logind.service \
	systemd-remount-fs.service \
	systemd-udev-hwdb-update.service \
	systemd-udevd.service \
	systemd-vconsole-setup.service

dnf install -y --skip-broken \
  autoconf \
  automake \
  conntrack-tools \
  dhcp-client \
  dnf-utils \
  file \
  fping \
  frr \
  gcc \
  gettext-devel \
  git \
  glibc-langpack-en \
  hostname \
  iproute \
  iputils \
  iptables \
  js-d3-flame-graph \
  libcap-devel \
  libreswan \
  libtool \
  libxslt \
  lksctp-tools-devel \
  make \
  meson \
  net-tools.x86_64 \
  ninja-build \
  nmap \
  openssh-clients \
  openssh-server \
  openssl \
  openssl-devel \
  perf \
  procps-ng \
  python3 \
  python3-devel \
  python3-pip \
  python3-psutil \
  python3-six \
  tcpdump \
  unbound-devel \
  uuid.x86_64 \
  which  \
  initscripts

# Generate variation of dhclient-script that we can use for fake vm namespaces.
# dhclient-script might not be available though, so don't fail if that's
# the case.
mkdir -pv /bin
/tmp/generate_dhclient_script_for_fullstack.sh / || \
    echo "Failed to generate dhclient script for fullstack!"
