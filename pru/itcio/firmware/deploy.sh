#!/bin/bash

##############################################################################
#
# Copyright (C) 2016 Zubeen Tolani <ZeekHuge - zeekhuge@gmail.com>
#
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
#
#	* Redistributions of source code must retain the above copyright
#	  notice, this list of conditions and the following disclaimer.
#
#	* Redistributions in binary form must reproduce the above copyright
#	  notice, this list of conditions and the following disclaimer in the
#	  documentation and/or other materials provided with the
#	  distribution
#
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
# "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
# LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
# A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
# OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
# SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
# LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
# DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
# THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
# (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
# OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
#
#############################################################################


# The script configures the pinmuxing for PINS and reboots PRUs 
#Dont change. If changing these variables, make sure the given pin can be muxed to the given pru.  

HEADER=P8_
PINS="27 28 29 39 40 41 42 43 44 45 46"

#PRU_CORE should be either 0 or 1
PRU_CORE=1

echo "*******************************************************"
echo "This must be compiled on the BEAGLEBONE BLACK itself"
echo "It was tested on 4.4.11-ti-r29 kernel version"
echo "The source code for n-blinky-fw is based on examples from"
echo "pru-software-support-package which can be cloned from"
echo "git clone git://git.ti.com/pru-software-support-package/pru-software-support-package.git"
echo ""
echo "n-blinky-fw along with the kernel module will toggle all the PRU0 gpios routed to P8"
echo "n number of times where n is the input to /dev/rpmsg_pru_itcio" 
echo "For more details see README.md"

echo "-Placing the firmware"
	cp gen/*.out /lib/firmware/am335x-pru$PRU_CORE-fw

echo "-Configuring pinmux"
	for PIN_NUMBER in $PINS
	do
		config-pin -a $HEADER$PIN_NUMBER pruout
		config-pin -q $HEADER$PIN_NUMBER
	done

echo "-Rebooting"
	if [ $PRU_CORE -eq 0 ]
	then
		echo "Rebooting pru-core 0"
		echo "4a334000.pru0" > /sys/bus/platform/drivers/pru-rproc/unbind 2>/dev/null
		echo "4a334000.pru0" > /sys/bus/platform/drivers/pru-rproc/bind
	else
		echo "Rebooting pru-core 1"
		echo "4a338000.pru1"  > /sys/bus/platform/drivers/pru-rproc/unbind 2> /dev/null
		echo "4a338000.pru1" > /sys/bus/platform/drivers/pru-rproc/bind
	fi

echo "******************************************************************************"
echo "Done. Incremented packet echo via"
echo "echo pktdata > /dev/itc/packets"
echo "******************************************************************************"
