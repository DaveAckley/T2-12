#!/bin/bash

TAG="BOOT2[$$]"
echo $TAG "/home/t2/T2-12/apps/t2/t2/t2 STARTING"
echo $TAG "whoami=`whoami`"
while [ ! -e /dev/fb0 ] ; do
    sleep 5
    logger -s -t $TAG "WAITING FOR /dev/fb0"
done
echo $TAG "/dev/fb0 EXISTS"
sleep 1
    
sleep 1
lsmod | grep itc
sleep 1

echo $TAG "STARTING PRUS"
sleep 1
echo 'start' > /sys/class/remoteproc/remoteproc1/state
echo 'start' > /sys/class/remoteproc/remoteproc2/state
sleep 1
echo $TAG "PRUS AWAY"

printf "OTHER STUB STUFF IN FUTURE HERE\n"
