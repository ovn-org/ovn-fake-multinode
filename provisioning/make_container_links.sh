#!/usr/bin/env bash

[ $EUID -eq 0 ] || { echo 'must be root' >&2; exit 1; }

# make_container_links.sh
#
# This script uses mounts from docker inspect and creates
# symbolic links for all directories it finds under $BASE_DIR
#
# Usage: $0 [BASE_DIR]
#

#set -o xtrace
set -o errexit

BASE_DIR=${1:-'/tmp/cmounts'}
SAFE_CHECK_FILE="${BASE_DIR}/$(basename $0).washere"
[ ! -e ${BASE_DIR} ] || [ -e "${SAFE_CHECK_FILE}" ] || { echo "cowardly bailing: ${SAFE_CHECK_FILE} not found" >&2; exit 1; }
rm -rf ${BASE_DIR} ; mkdir -p ${BASE_DIR} ; touch "${SAFE_CHECK_FILE}"

for CID in $(docker ps --no-trunc --quiet); do
    CNAME=$(docker ps --no-trunc --filter "id=${CID}" --format {{.Names}})
    MOUNTS=$(docker inspect ${CID} | grep -B1 '"Destination": "/' | grep -A1 '"Source": "/' | tr -d [:space:])
    echo "Creating mount links: ${BASE_DIR}/${CNAME}"
    mkdir -p "${BASE_DIR}/${CID}"
    [ -n "${CNAME}" ] && ln -s ${CID} "${BASE_DIR}/${CNAME}"
    delimiter='Source":'
    string=$MOUNTS$delimiter
    myarray=()
    while [[ $string ]]; do
	myarray+=( "${string%%"$delimiter"*}" )
	string=${string#*"$delimiter"}
    done
    for value in ${myarray[@]}; do
        CONTAINER_PATH=$(echo "$value" | cut -d\" -f6)
	CONTAINER_DIR=$(dirname "$CONTAINER_PATH")
	CONTAINER_BASE=$(basename "$CONTAINER_PATH")
	DEST_DIR=$(echo "$value" | cut -d\" -f2)
	[ -n "${CONTAINER_BASE}" ] && [ -d "${DEST_DIR}" ] && {
	    mkdir -p "${BASE_DIR}/${CID}${CONTAINER_DIR}"
	    ln -s "${DEST_DIR}" "${BASE_DIR}/${CID}/${CONTAINER_PATH}" ||:
	}
    done
done
