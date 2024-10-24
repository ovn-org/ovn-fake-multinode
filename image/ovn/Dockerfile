FROM ovn/cinc
MAINTAINER "Numan Siddique" <numans@ovn.org>

ARG OVS_SRC_PATH
ARG OVN_SRC_PATH
ARG USE_OVN_RPMS
ARG USE_OVN_DEBS
ARG EXTRA_OPTIMIZE
ARG INSTALL_UTILS_FROM_SOURCES
ARG USE_OVSDB_ETCD

COPY $OVS_SRC_PATH /ovs
COPY $OVN_SRC_PATH /ovn

COPY README.md *.rpm /
COPY README.md *.deb /
COPY install_ovn.sh /install_ovn.sh
COPY install_utils_from_sources.sh /install_utils_from_sources.sh
COPY install_ovsdb_etcd.sh /install_ovsdb_etcd.sh
COPY install_etcd.sh /install_etcd.sh
COPY run_ovsdb_etcd.sh /run_ovsdb_etcd.sh
COPY run_ovsdb_etcd_sb.sh /run_ovsdb_etcd_sb.sh
COPY run_ovsdb_etcd_nb.sh /run_ovsdb_etcd_nb.sh

RUN /install_ovn.sh $USE_OVN_RPMS $USE_OVN_DEBS $EXTRA_OPTIMIZE
RUN /install_utils_from_sources.sh $INSTALL_UTILS_FROM_SOURCES
RUN /install_ovsdb_etcd.sh
RUN /install_etcd.sh

# Rely on the default way of starting each service from the ovn_cluster
# script. This is a workaround to avoid major changes on the ovn_cluster
# script and may be improved in the future.
RUN if [ "$USE_OVN_RPMS" = "yes" ] || [ "$USE_OVN_DEBS" = "yes" ] ; then \
        /usr/bin/systemctl disable ovn-central && \
        /usr/bin/systemctl disable ovn-ic-db && \ 
        /usr/bin/systemctl disable ovn-ic && \
        /usr/bin/systemctl disable openvswitch-switch && \
        /usr/bin/systemctl disable ovn-host ; \
    fi

VOLUME ["/var/log/openvswitch", \
"/var/lib/openvswitch", "/var/run/openvswitch", "/etc/openvswitch", \
"/var/log/ovn", "/var/lib/ovn", "/var/run/ovn", "/etc/ovn"]
