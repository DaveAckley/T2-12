#!/bin/bash

echo "-Placing firmware for PRU${PRU_CORE}"
	cp gen/main_pru${PRU_CORE}_fw.out /lib/firmware/am335x-pru$PRU_CORE-fw

echo "-Rebooting PRU${PRU_CORE}"
	if [ $PRU_CORE -eq 0 ]
	then
		echo "4a334000.pru0" > /sys/bus/platform/drivers/pru-rproc/unbind 2>/dev/null
		echo "4a334000.pru0" > /sys/bus/platform/drivers/pru-rproc/bind
	else
		echo "4a338000.pru1"  > /sys/bus/platform/drivers/pru-rproc/unbind 2> /dev/null
		echo "4a338000.pru1" > /sys/bus/platform/drivers/pru-rproc/bind
	fi

