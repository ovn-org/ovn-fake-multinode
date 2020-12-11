#!/usr/bin/env bash

set -o errexit
#set -o xtrace

[ -e /dev/kvm ] || { echo "PROBLEM, you need to ensure hv can nest"; exit 1; }
grep -q Y /sys/module/kvm_intel/parameters/nested || \
grep -q 1 /sys/module/kvm_intel/parameters/nested || {
  sudo rmmod kvm-intel
  sudo sh -c "echo 'options kvm-intel nested=y' >> /etc/modprobe.d/dist.conf"
  sudo modprobe kvm-intel
}
[ -e /sys/module/kvm_intel ] && {
  modinfo kvm_intel | grep -q 'nested:' || { echo "PROBLEM, nesting did not enable"; exit 1; }
} ||:

