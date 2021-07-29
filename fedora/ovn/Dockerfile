FROM ovn/cinc
MAINTAINER "Numan Siddique" <numans@ovn.org>

ARG OVS_SRC_PATH
ARG OVN_SRC_PATH
ARG USE_OVN_RPMS
ARG EXTRA_OPTIMIZE
ARG INSTALL_UTILS_FROM_SOURCES
ARG USE_OVSDB_ETCD

COPY $OVS_SRC_PATH /ovs
COPY $OVN_SRC_PATH /ovn

COPY *.rpm /
COPY install_ovn.sh /install_ovn.sh
COPY install_utils_from_sources.sh /install_utils_from_sources.sh
COPY install_ovsdb_etcd.sh /install_ovsdb_etcd.sh
COPY install_etcd.sh /install_etcd.sh
COPY run_ovsdb_etcd.sh /run_ovsdb_etcd.sh
COPY run_ovsdb_etcd_sb.sh /run_ovsdb_etcd_sb.sh
COPY run_ovsdb_etcd_nb.sh /run_ovsdb_etcd_nb.sh

RUN /install_ovn.sh $USE_OVN_RPMS $EXTRA_OPTIMIZE
RUN /install_utils_from_sources.sh $INSTALL_UTILS_FROM_SOURCES
RUN /install_ovsdb_etcd.sh
RUN /install_etcd.sh

VOLUME ["/var/log/openvswitch", \
"/var/lib/openvswitch", "/var/run/openvswitch", "/etc/openvswitch", \
"/var/log/ovn", "/var/lib/ovn", "/var/run/ovn", "/etc/ovn"]
