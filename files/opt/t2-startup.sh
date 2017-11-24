#!/bin/bash

# Run final boot time configurations for T2 pins

logger STARTING T2 FINAL BOOT CONFIG

logger T2 FINAL BOOT CONFIG: cape-universal2
echo cape-universal2 > /sys/devices/platform/bone_capemgr/slots
sleep 2

logger T2 FINAL BOOT CONFIG: boot-config-pin
config-pin -f /opt/scripts/t2/boot-config-pin.txt
sleep 2

logger T2 FINAL BOOT CONFIG: ADC
echo T2-ADC > /sys/devices/platform/bone_capemgr/slots
sleep 2

logger T2 FINAL BOOT CONFIG: waveshare35a
echo waveshare35a > /sys/devices/platform/bone_capemgr/slots

logger T2 FINAL BOOT CONFIG: PRUs
echo "Rebooting PRUs"
echo "4a334000.pru0" > /sys/bus/platform/drivers/pru-rproc/unbind 2>/dev/null
echo "4a338000.pru1"  > /sys/bus/platform/drivers/pru-rproc/unbind 2> /dev/null
echo "4a338000.pru1" > /sys/bus/platform/drivers/pru-rproc/bind
echo "4a334000.pru0" > /sys/bus/platform/drivers/pru-rproc/bind

logger T2 FINAL BOOT CONFIG FINISHED

exit 0
