#!/bin/bash

#            DO WHAT THE FUCK YOU WANT TO PUBLIC LICENSE
#                    Version 2, December 2004
#
# Copyright (C) 2019 Red Hat, Inc.
#
# Everyone is permitted to copy and distribute verbatim or modified
# copies of this license document, and changing it is allowed as long
# as the name is changed.
#
#            DO WHAT THE FUCK YOU WANT TO PUBLIC LICENSE
#   TERMS AND CONDITIONS FOR COPYING, DISTRIBUTION AND MODIFICATION
#
#  0. You just DO WHAT THE FUCK YOU WANT TO.

udevadm trigger
udevadm settle

# iterate over all interfaces and set them up
readarray -t interfaces < <(ip l | awk -F ":" '/^[0-9]+:/{dev=$2 ; if ( dev !~ /^ lo$/) {print $2}}')
for iface in "${interfaces[@]// /}"
do
    /sbin/ifup $iface
done

############################################################
# Helper to query and write the ignition config
############################################################
function get_ignition_file() {
    # first collect all info from introspection
    local INTROSPECTION_OUTPUT=$(ghwc -f json)

    # then send the information to the introspection endpoint and collect ign
    FINAL_IGNITION=$(curl --connect-timeout 5 --retry 10 --retry-delay 30 -d "$INTROSPECTION_OUTPUT" -H "Content-Type: application/json" -X POST ${INTROSPECTION_ENDPOINT})
    echo "${FINAL_IGNITION}" > /tmp/config.ign

    # override ignition url with file path
    echo "file:///tmp/config.ign" > /tmp/ignition_url

    echo "final configuration is"
    cat /tmp/config.ign
    echo "ignition url is"
    cat /tmp/ignition_url
}

############################################################
#Get the ignition url to install
############################################################
echo "Getting ignition url" >> /tmp/debug
INTROSPECTION_ENDPOINT=$(cat /tmp/introspection_endpoint)
rm -f /tmp/introspection_endpoint

##############################
# Query for the ignition file
##############################
echo "Querying for ignition endpoint" >> /tmp/debug
get_ignition_file
