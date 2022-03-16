#!/bin/bash

# 2022-03-16 J.Nider
#
# Collect interesting information about this machine

cleanup=1
ssh_dir=/home/$user/.ssh
IDENTITY=${identity:+"-i $identity"}

function usage()
{
	echo "-a <admin>"
	echo "-c <cleanup>"
	echo "-h"
	echo "-i <identity>"
	echo "-r <remote>"
	echo "-v <verbose>"
}

while getopts "a:chi:r:v" params; do
	case "$params" in
	a)
		admin=${OPTARG}
		;;

	c)
		cleanup=${OPTARG}
		;;

	h)
		usage
		exit 0
		;;

	i)
		identity=${OPTARG}
		;;

	r)
		remote=${OPTARG}
		;;

	v)
		VERBOSE=1
		;;
	esac
done

if [[ "$VERBOSE" ]]; then
	echo "admin=$admin"
	echo "identity=$identity"
	echo "remote=$remote"
fi

if [[ ! -z $remote ]]; then
	if [[ -z $admin ]]; then
		echo "You must provide an admin account name (-a) for the remote machine"
		exit
	fi

	echo "copying script to $remote:/tmp"
	# copy myself to the remote machine
	cmd="scp $IDENTITY $0 $key $admin@$remote:/tmp"
	[[ "$VERBOSE" ]] && echo $cmd
	$cmd
	if [[ $? != 0 ]]; then
		echo "Error copying script to $remote:/tmp"
		exit
	fi

	# execute myself on the remote machine
	[[ "$VERBOSE" ]] && echo "Executing on remote machine"
	exe_name=${0##*/}
	cmd="ssh $IDENTITY $admin@$remote sudo /tmp/$exe_name ${cleanup:+\"-c\"}"
	[[ "$VERBOSE" ]] && echo "$cmd"
	archive_name=$($cmd)
	echo "Archive in: $archive_name"
	cmd="scp $IDENTITY $admin@$remote:/$archive_name ."
	[[ "$VERBOSE" ]] && echo "$cmd"
	$cmd
	echo "Done!"
	exit
fi

# general
cat /proc/version > version.txt
hostname > hostname.txt

# CPU
cat /proc/cpuinfo > cpuinfo.txt

# memory
cat /proc/meminfo > meminfo.txt

# PCI
lspci > pci.txt

# USB
lsusb > usb.txt

# network config
ip addr > ipconfig.txt

# create archive
archive_name=$(date -I)-$(hostname).tar.bz2
tar cjf $archive_name version.txt hostname.txt cpuinfo.txt meminfo.txt pci.txt usb.txt ipconfig.txt

# return the name to the caller so we know which file to copy
echo $(realpath $archive_name)
