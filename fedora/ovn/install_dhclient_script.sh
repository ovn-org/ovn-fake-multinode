#!/usr/bin/env bash

set -o errexit
#set -o xtrace

mkdir -pv /bin
cd "$(dirname $0)"
./generate_dhclient_script_for_fullstack.sh /
