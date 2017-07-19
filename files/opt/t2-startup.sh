#!/bin/bash

# Run final boot time configurations for T2 pins

logger STARTING T2 FINAL BOOT CONFIG

logger T2 FINAL BOOT CONFIG: cape-universal2
echo cape-universal2 > /sys/devices/platform/bone_capemgr/slots
sleep 2

logger T2 FINAL BOOT CONFIG: boot-config-pin
config-pin -f /opt/scripts/t2/boot-config-pin.txt
sleep 2

logger T2 FINAL BOOT CONFIG: waveshare35a
echo waveshare35a > /sys/devices/platform/bone_capemgr/slots
sleep 2

fbi -d /dev/fb0 -T 1 -noverbose -a /opt/scripts/t2/t2-splash.png

logger T2 FINAL BOOT CONFIG FINISHED

exit 0
