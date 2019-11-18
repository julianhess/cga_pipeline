#!/bin/bash

#
# usage: nfs_provision_worker.sh <hostname of server>

SHOST=$1

# should already be present, but check just in case
[ ! -d /mnt/nfs ] && sudo mkdir -p /mnt/nfs
sudo mount -o defaults,hard,intr ${SHOST}:/mnt/nfs /mnt/nfs