FROM ovn/cinc
MAINTAINER "Numan Siddique" <numans@ovn.org>

ARG OVS_SRC_PATH
ARG OVN_SRC_PATH

#RUN dnf install @'Development Tools' -y
RUN dnf -y install automake make gcc autoconf openssl-devel \
  python3 libtool openssl iputils \
  net-tools.x86_64 uuid.x86_64 iproute.x86_64 dnf-utils \
  file

RUN pip3 install six

COPY $OVS_SRC_PATH /ovs
COPY $OVN_SRC_PATH /ovn

COPY install_ovn.sh /install_ovn.sh

RUN /install_ovn.sh

RUN dnf -y remove automake make gcc autoconf openssl-devel libtool

VOLUME ["/var/log/openvswitch", \
"/var/lib/openvswitch", "/var/run/openvswitch", "/etc/openvswitch", \
"/var/log/ovn", "/var/lib/ovn", "/var/run/ovn", "/etc/ovn"]
#ENTRYPOINT ["start-ovn"]
