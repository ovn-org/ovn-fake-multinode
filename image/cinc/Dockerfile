#
# Image configured with systemd. Useful for
# simulating multinode deployments.
#
# The standard name for this image is ovn/cinc
#

ARG OS_IMAGE
FROM $OS_IMAGE

# Pass OS_IMAGE to build scripts too.
ARG OS_IMAGE
ARG OS_BASE

# Fix 'WARNING: terminal is not fully functional' when TERM=dumb
ENV TERM=xterm

VOLUME ["/run", "/tmp"]

STOPSIGNAL SIGRTMIN+3
COPY image/cinc/generate_dhclient_script_for_fullstack.sh /tmp/generate_dhclient_script_for_fullstack.sh

COPY image/cinc/install_"$OS_BASE"_pkg.sh /install_pkg.sh
RUN /install_pkg.sh $OS_IMAGE

RUN mkdir -p /usr/local/bin

CMD ["/usr/sbin/init"]
