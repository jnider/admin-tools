#!/bin/bash

# 2016-05-11 J.Nider
# Script to help select the correct ETHx interfaces on the host
#-------------------------

# get a list of all eth interfaces (driver must be installed & bound to a device to see these)
ifs=$(ls /sys/class/net)

for iface in $ifs; do
   pci_addr=$(realpath /sys/class/net/$iface | sed 's_/sys/devices/pci.*\/\(.*\)/net/.*_\1_')

   # only print PCI devices
   if [[ $pci_addr ]]; then
      dev_name=$(lspci -D | grep $pci_addr | sed 's_.*: \(.*\)_\1_')
      eth_addr=$(ip link show $iface | grep 'link' | awk '{print $2}')
      echo "$iface ($eth_addr) : $dev_name"
   fi
done
