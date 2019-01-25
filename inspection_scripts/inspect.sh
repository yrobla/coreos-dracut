#!/bin/bash

# retrieve output of disks
DISKS="$(/bin/lsblk -abi -o KNAME,MODEL,SERIAL,SIZE,STATE,ROTA,TYPE,WWN,VENDOR -d |  sed -e 's/\s\+/ /g' | jq -rRs 'split("\n")[1:-1] | map([split(" ")[]] | {"name":.[0], "model": .[1], "serial": .[2], "size": .[3], "state": .[4], "rota": .[5], "type": .[6], "wwn": .[7], "vendor": .[8]})')"

