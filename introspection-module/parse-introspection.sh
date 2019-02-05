#!/bin/sh

. /lib/dracut-lib.sh

local INTROSPECTION_ENDPOINT=$(getarg coreos.introspection_endpoint=)
if [ ! -z "$INTROSPECTION_ENDPOINT" ]
then
	echo "preset introspection endpoint to $INTROSPECTION_ENDPOINT" >> /tmp/debug
	echo $INTROSPECTION_ENDPOINT >> /tmp/introspection_endpoint
fi
