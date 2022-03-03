#!/bin/sh
# Busybox udhcpc dispatcher script.
# Copyright (C) 2009 by Axel Beckert.
# Copyright (C) 2014 by Michael Tokarev.
# Copyright (C) 2022 by Tom Wimmenhove.
#
# Based on the busybox example scripts and the old udhcp source
# package default.* scripts.

RESOLV_CONF="/etc/resolv.conf"
IGNORE_RESOLV=true
NET="1.1.1.1/32"

log() {
    logger -t "udhcpc[$PPID]" -p daemon.$1 "$interface: $2"
}

case $1 in
    bound|renew)

	# Configure new IP address.
	# Do it unconditionally even if the address hasn't changed,
	# to also set subnet, broadcast, mtu, ...
	busybox ifconfig $interface ${mtu:+mtu $mtu} \
	    $ip netmask $subnet ${broadcast:+broadcast $broadcast}

	# get current ("old") routes (after setting new IP)
	crouter=$(busybox ip -4 route show dev $interface |
	          busybox awk '$1 == "default" { print $3; }')
	router="${router%% *}" # linux kernel supports only one (default) route
	if [ ".$router" != ".$crouter" ]; then
	    # reset just default routes
	    busybox ip -4 route flush exact $NET dev $interface
	fi
	if [ -n "$router" ]; then
	    # special case for /32 subnets: use onlink keyword
	    [ ".$subnet" = .255.255.255.255 ] \
		    && onlink=onlink || onlink=
	    busybox ip -4 route add $NET via $router dev $interface $onlink
	fi

	# Update resolver configuration file
	[ -n "$domain" ] && R="domain $domain" || R=""
	for i in $dns; do
	    R="$R
nameserver $i"
	done

	if [ $IGNORE_RESOLV != true ] ; then
		if [ -x /sbin/resolvconf ]; then
		    echo "$R" | resolvconf -a "$interface.udhcpc"
		else
		    echo "$R" > "$RESOLV_CONF"
		fi
	fi

	log info "$1: IP=$ip/$subnet router=$router domain=\"$domain\" dns=\"$dns\" lease=$lease"
	;;

    deconfig)
	busybox ip link set $interface up
	busybox ip -4 addr flush dev $interface
	busybox ip -4 route flush dev $interface
	[ -x /sbin/resolvconf ] &&
	    resolvconf -d "$interface.udhcpc"
	log notice "deconfigured"
	;;

    leasefail | nak)
	log err "configuration failed: $1: $message"
	;;

    *)
	echo "$0: Unknown udhcpc command: $1" >&2
	exit 1
	;;
esac
