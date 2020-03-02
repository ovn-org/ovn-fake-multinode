#
# Image configured with systemd and docker-in-docker.  Useful for
# simulating multinode deployments.
#
# The standard name for this image is openshift/dind
#
# Notes:
#
#  - disable SELinux on the docker host (not compatible with dind)
#
#  - to use the overlay graphdriver, ensure the overlay module is
#    installed on the docker host
#
#      $ modprobe overlay
#
#  - run with --privileged
#
#      $ docker run -d --privileged openshift/dind
#

FROM fedora:31

# Fix 'WARNING: terminal is not fully functional' when TERM=dumb
ENV TERM=xterm

## Configure systemd to run in a container

ENV container=docker

VOLUME ["/run", "/tmp"]

STOPSIGNAL SIGRTMIN+3

RUN systemctl mask\
 auditd.service\
 console-getty.service\
 dev-hugepages.mount\
 dnf-makecache.service\
 docker-storage-setup.service\
 getty.target\
 lvm2-lvmetad.service\
 sys-fs-fuse-connections.mount\
 systemd-logind.service\
 systemd-remount-fs.service\
 systemd-udev-hwdb-update.service\
 systemd-udev-trigger.service\
 systemd-udevd.service\
 systemd-vconsole-setup.service

## RUN cp /usr/lib/systemd/system/dbus.service /etc/systemd/system/;\
## sed -i 's/OOMScoreAdjust=-900//' /etc/systemd/system/dbus.service
COPY dbus.service /etc/systemd/system/

# Remove non-english translations (by explicitly installing just the English
# ones) for glibc to reduce image size by 100mb.  Also install various network
# utils for network debugging.
RUN dnf -y update && dnf -y install\
 docker\
 glibc-langpack-en\
 iptables\
 openssh-clients\
 openssh-server\
 pacemaker pcs resource-agents\
 tcpdump\
 dhclient\
 which\
 fping\
 perf

#RUN dnf install @'Development Tools' -y
RUN dnf -y install automake make gcc autoconf openssl-devel \
  python3 libtool openssl iputils  python3-pip \
  net-tools.x86_64 uuid.x86_64 iproute.x86_64 dnf-utils libreswan

RUN pip3 install six
## Configure docker

RUN systemctl enable docker.service
RUN systemctl enable pcsd.service

# Default storage to vfs.  overlay will be enabled at runtime if available.
RUN echo "DOCKER_STORAGE_OPTIONS=--storage-driver vfs" >\
 /etc/sysconfig/docker-storage

RUN mkdir -p /usr/local/bin
COPY dind-setup.sh /usr/local/bin/
COPY dind-setup.service /etc/systemd/system/
RUN systemctl enable dind-setup.service

# Generate variation of dhclient-script that we can use for fake vm namespaces
RUN mkdir -pv /bin
COPY fedora/cinc/generate_dhclient_script_for_fullstack.sh /tmp/generate_dhclient_script_for_fullstack.sh
RUN /tmp/generate_dhclient_script_for_fullstack.sh /
RUN dnf -y remove which

VOLUME ["/var/lib/docker"]

# Hardlink init to another name to avoid having oci-systemd-hooks
# detect containers using this image as requiring read-only cgroup
# mounts.  containers running docker need to be run with --privileged
# to ensure cgroups are mounted with read-write permissions.
RUN ln /usr/sbin/init /usr/sbin/dind_init

COPY dind_wrapper_init /usr/sbin/dind_wrapper_init
CMD ["/usr/sbin/dind_wrapper_init"]
