#!/bin/sh
# iStoreOS boot helper - E87N fixed version
# FIX: overlay must be fstools rootfs_data (p5 remainder), NOT partition 3.
# On EdgePi E87N, partition 3 (mmcblk0p3) is the FIP / U-Boot partition.
# The stock iStoreOS code hardcodes partition 3 as overlay, which erases U-Boot
# on every boot.  Use /dev/rootfs_data (created by fstools on the rootfs
# partition) instead.

# > getbootdisk
# mmcblk0
_getbootdisk()
{
	local rootpart="`grep -Fm1 ' - squashfs /dev/root ' /proc/self/mountinfo | cut -d' ' -f3`"
	[ -z "$rootpart" ] && return 1
	local devpath="`readlink /sys/dev/block/$rootpart`"
	[ -z "$devpath" ] && return 1
	rootpart="${devpath##*/}"
	devpath="${devpath%%/$rootpart}"
	local rootdisk="${devpath##*/}"
	echo "$rootdisk"
}

# > getbootdisk_lvm
# dm-0
_getbootdisk_lvm()
{
	local rootpart
	if [ -e /rom/note ]; then
		rootpart="`grep -Fm1 ' / / ' /proc/self/mountinfo | grep -F ' - squashfs ' | cut -d' ' -f3`"
	else
		rootpart="`grep -Fm1 ' / /rom ' /proc/self/mountinfo | grep -F ' - squashfs ' | cut -d' ' -f3`"
	fi
	[ -z "$rootpart" ] && return 1
	local major=${rootpart%%:*}
	local minor=${rootpart##*:}
	minor="$(( $minor & 0xfffc ))"
	local devpath="`readlink /sys/dev/block/$major:$minor`"
	[ -z "$devpath" ] && return 1
	local rootdisk="${devpath##*/}"
	echo "$rootdisk"
}

# > getpartofdisk sda 3
# sda3
# > getpartofdisk mmcblk0 3
# mmcblk0p3
_getpartofdisk()
{
	local disk="$1" offset="$2" part
	if [[ "$offset" = 0 ]]; then
		echo "$disk"
	else
		part="$disk"
		echo "$part" | grep -q '^.*[0-9]$' && part="${part}p"
		part="${part}"$(( ${offset} ))
		if [ ! -b "/dev/$part" ]; then
			local line
			local MAJOR MINOR DEVNAME DEVTYPE
			while read line; do
				export -n "$line"
			done < "/sys/block/$disk/uevent"
			local devpath="`readlink /sys/dev/block/$MAJOR:$(($MINOR + $offset))`"
			if [ -n "$devpath" ]; then
				part="${devpath##*/}"
			fi
		fi
		echo "$part"
	fi
	return 0
}

_get_overlay_partition_default()
{
	local bootdisk="`_getbootdisk`"
	[ -z "$bootdisk" ] && {
		log "getbootdisk failed, try lvm"
		bootdisk="`_getbootdisk_lvm`"
	}
	[ -z "$bootdisk" ] && {
		log "getbootdisk_lvm failed"
		return 1
	}
	if [ ! -e "/sys/block/$bootdisk/uevent" ]; then
		log "/sys/block/$bootdisk/uevent does not exist"
		return 1
	fi
	if [ -e /rom/note ]; then
		cat "/sys/block/$bootdisk/uevent" > /tmp/.bootdisk
	fi
	# E87N FIX: do NOT use partition 3 (that is the FIP/U-Boot partition).
	# Use fstools rootfs_data (created on the rootfs partition's free space).
	if [ -b /dev/rootfs_data ]; then
		OVERLAY_DEV="/dev/rootfs_data"
		return 0
	fi
	log "rootfs_data not available, fall back"
	return 1
}

_get_overlay_partition_fallback()
{
	log "get_overlay_partition_fallback"
	rm -f /tmp/.bootdisk >/dev/null 2>&1
	# E87N FIX: do not fall back to partition 3 (fip).  Return failure so the
	# standard OpenWrt rootfs_data / ramoverlay path is used instead.
	return 1
}

get_overlay_partition()
{
	[ -e /.dockerenv ] && {
		log "No overlay partition in Docker"
		return 1
	}
	_get_overlay_partition_default || _get_overlay_partition_fallback || {
		log "Unable to determine overlay partition"
		return 1
	}
	return 0
}
