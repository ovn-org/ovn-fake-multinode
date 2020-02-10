FROM ovn/cinc
MAINTAINER "Numan Siddique" <numans@ovn.org>

ARG OVS_SRC_PATH
ARG OVN_SRC_PATH
ARG USE_OVN_RPMS

COPY $OVS_SRC_PATH /ovs
COPY $OVN_SRC_PATH /ovn

COPY *.rpm /
COPY install_ovn.sh /install_ovn.sh

RUN /install_ovn.sh $USE_OVN_RPMS

# Generate variation of dhclient-script that we can use for fake vm namespaces
RUN dnf -y install dhclient which
COPY fedora/ovn/generate_dhclient_script_for_fullstack.sh /tmp/generate_dhclient_script_for_fullstack.sh
COPY fedora/ovn/install_dhclient_script.sh /tmp/install_dhclient_script.sh
RUN /tmp/install_dhclient_script.sh /

RUN dnf -y remove automake make gcc autoconf openssl-devel libtool which

VOLUME ["/var/log/openvswitch", \
"/var/lib/openvswitch", "/var/run/openvswitch", "/etc/openvswitch", \
"/var/log/ovn", "/var/lib/ovn", "/var/run/ovn", "/etc/ovn"]
