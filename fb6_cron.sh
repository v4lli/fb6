#!/bin/sh
# Probably only works on OpenBSD, because of the rc-scripts
# !!! Use with caution! This is nothing more than a quick&dirty hack. !!!

set -eu

FB_PASSWORD=toortoor
ADDR_FILE=/tmp/fbv6_addr
DHCP6C_PID=/var/run/dhcp6c.pid
BASEDIR=$(dirname $0)

# XXX check for root

if ! [ -f "$ADDR_FILE" ]; then
	touch $ADDR_FILE
fi

get_addr() {
	# XXX Expects only one publicly routable address on that interface
	# XXX There surely is a better way for the following
	ifconfig $1 | grep 'inet6 2' | tr -s ' ' | cut -d ' ' -f2
}

get_net() {
	# XXX This probably should not involve any kind of text processing
	get_addr $1 | cut -d ':' -f1-4
}

addrdump() {
	local our_addr=$(get_addr vr3)
	echo "our_addr= $our_addr"
	local our_net=$(get_net vr3)
	echo "our_net = $our_net"

	echo -n "rtadvd "
	if sh /etc/rc.d/rtadvd check ; then
		echo running
	else
		echo not running
	fi
}

# XXX Again, there surely is a better way for this
EXT_ADDR=$($BASEDIR/fb_ifconfig.expect "$(FB_PASSWORD)" | grep -A5 '^dsl' | grep 'inet6 addr.*Scope:Global' | head -1 | tr -s ' ' | cut -d ' ' -f 4)
if [ "$EXT_ADDR" != "$(cat $ADDR_FILE)" ]; then
	echo $EXT_ADDR > $ADDR_FILE

	sh /etc/rc.d/rtadvd stop > /dev/null || true
	if [ -f "$DHCP6C_PID" ]; then
		kill -TERM $(cat $DHCP6C_PID)
	else
		#echo "dhcp6c not runnign? Can't unconfigure old prefix..."
		true
	fi

	# XXX Wait for PID file instead of sleeping blindly
	sleep 1
	/usr/local/sbin/dhcp6c -c /etc/dhcp6c.conf vr2
	sleep 1

	$BASEDIR/fb_add_route.expect "$(FB_PASSWORD)" "$(get_net vr3)" > /dev/null

	sh /etc/rc.d/rtadvd start > /dev/null

	# XXX These two should be necessary only once, not every time
	# XXX the script is executed
	# XXX Replace with correct link-local address!
	route add -inet6 default fe80::2%vr2 2>/dev/null > /dev/null || true
	pfctl -a v6out -f /etc/pf.v6out.conf
fi
