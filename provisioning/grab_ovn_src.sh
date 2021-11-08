#!/usr/bin/env bash

set -o xtrace
set -o errexit

function grab_src {
    SRC_DIR=$1
    BRANCH=$2
    REPO=$3

    if [ ! -d ./${SRC_DIR} ]; then
	git clone --depth 1 --no-single-branch -b $BRANCH $REPO $SRC_DIR
    fi
}

OVS_GIT_REPO=${OVS_GIT_REPO:-https://github.com/openvswitch/ovs}
OVS_BRANCH=${OVS_BRANCH:-master}
OVN_GIT_REPO=${GIT_REPO:-https://github.com/ovn-org/ovn}
OVN_BRANCH=${OVN_BRANCH:-main}

cd /vagrant
grab_src ovs $OVS_BRANCH $OVS_GIT_REPO
grab_src ovn $OVN_BRANCH $OVN_GIT_REPO
