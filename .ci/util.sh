#!/bin/bash

function sudo_preserve_env()
{
    sudo sh -c 'cat > /etc/sudoers.d/ovn-fake-multinode-env' << EOF
Defaults env_keep += "RUNC_CMD OVN_SRC_PATH OVS_SRC_PATH OS_IMAGE OS_BASE CENTRAL_IC_ID"
EOF
    sudo chmod 0440 /etc/sudoers.d/ovn-fake-multinode-env
    sudo visudo -cf /etc/sudoers.d/ovn-fake-multinode-env
}
