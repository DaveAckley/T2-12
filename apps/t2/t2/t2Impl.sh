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
    
lsmod | grep itc

echo $TAG "STARTING PRUS"
prus=$(ls /sys/class/remoteproc/remoteproc[12]/state)
unset started
for pru in $prus ; do
    state=$(cat $pru)
    if [ "x$state" = "xoffline" ] ; then
	echo $TAG "Starting $pru"
	started="$started $pru"
	echo 'start' > $pru
	sleep 1
    else
	echo $TAG "$pru is $state, not starting it"
    fi
done

echo $TAG "Started $started"

echo $TAG "PRUS AWAY"

printf "OTHER STUB STUFF IN FUTURE HERE\n"
