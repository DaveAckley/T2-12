#!/bin/bash

# Run final boot time configurations for T2 pins

logger STARTING T2 FINAL BOOT CONFIG -- SORT OF

#logger T2 FINAL BOOT CONFIG: cape-universal2
#echo cape-universal2 > /sys/devices/platform/bone_capemgr/slots
#sleep 2

logger T2 FINAL BOOT CONFIG: boot-config-pin
config-pin -c /opt/scripts/t2/boot-config-pin.txt
#sleep 1

#logger T2 FINAL BOOT CONFIG: ADC
#echo T2-ADC > /sys/devices/platform/bone_capemgr/slots
#sleep 1

#logger T2 FINAL BOOT CONFIG: waveshare35a
#echo waveshare35a > /sys/devices/platform/bone_capemgr/slots

#logger T2 FINAL BOOT CONFIG: PRUs
#echo EXCEPT NOT BECAUSE THEY ARE ALREADY OK? 
echo "Rebooting PRUs"
#echo "4a334000.pru0" > /sys/bus/platform/drivers/pru-rproc/unbind 2>/dev/null
#echo "4a338000.pru1"  > /sys/bus/platform/drivers/pru-rproc/unbind 2> /dev/null
#sleep 1
#echo "4a338000.pru1" > /sys/bus/platform/drivers/pru-rproc/bind
#echo "4a334000.pru0" > /sys/bus/platform/drivers/pru-rproc/bind

sleep 1
echo start > /sys/class/remoteproc/remoteproc1/state
echo start > /sys/class/remoteproc/remoteproc2/state
 
#logger T2 FINAL BOOT CONFIG: CPUFREQ
#echo "Defaulting to 720MHz for heat management"
#cpufreq-set -f 720MHz

logger T2 FINAL BOOT CONFIG PENULTIMATE CONFIGURATION 

logger MASKING /dev/ttyO0 FROM FOGGEN SYSTEMD
systemctl mask serial-getty@ttyO0

logger ALSO MASKING /dev/ttyS0 FROM FOGGEN SYSTEMD
systemctl mask serial-getty@ttyS0

logger T2 FINAL BOOT CONFIG FINISHED

exit 0
