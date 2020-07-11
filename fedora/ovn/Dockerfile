FROM ovn/cinc
MAINTAINER "Numan Siddique" <numans@ovn.org>

ARG OVS_SRC_PATH
ARG OVN_SRC_PATH
ARG USE_OVN_RPMS
ARG EXTRA_OPTIMIZE

COPY $OVS_SRC_PATH /ovs
COPY $OVN_SRC_PATH /ovn

COPY *.rpm /
COPY install_ovn.sh /install_ovn.sh

RUN /install_ovn.sh $USE_OVN_RPMS $EXTRA_OPTIMIZE


VOLUME ["/var/log/openvswitch", \
"/var/lib/openvswitch", "/var/run/openvswitch", "/etc/openvswitch", \
"/var/log/ovn", "/var/lib/ovn", "/var/run/ovn", "/etc/ovn"]
