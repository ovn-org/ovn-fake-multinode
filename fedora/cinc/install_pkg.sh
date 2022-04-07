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

dnf -y install \
  autoconf \
  automake \
  conntrack-tools \
  dhcp-client \
  dnf-utils \
  file \
  fping \
  gcc \
  gettext-devel \
  git \
  glibc-langpack-en \
  hostname \
  iproute \
  iproute.x86_64 \
  iptables \
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
  python3-pip \
  resource-agents \
  tcpdump \
  uuid.x86_64 \
  which
