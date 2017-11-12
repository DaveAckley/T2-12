#
# Makefile written by Zubeen Tolani <ZeekHuge - zeekhuge@gmail.com>
# Copyright (C) 2016 Zubeen Tolani <ZeekHuge - zeekhuge@gmail.com>

# Modified by ackley@ackleyshack.com 2017.  See copyright info in
# rpmsg_pru_itcio.c in this directory.

#
# Makefile to compile rpmsg_pru_itcio.c
#

obj-m += rpmsg_pru_itcio.o

KDIR?=/lib/modules/$(shell uname -r)/build

ETC_MODULES_FILE:=/etc/modules-load.d/t2_12_modules.conf

all:	FORCE
	@make -C $(KDIR) M=$(CURDIR) modules

clean:	FORCE
	@make -C $(KDIR) M=$(CURDIR) clean

install:	all
	make INSTALL_MOD_DIR=itc -C /lib/modules/4.4.54-ti-r93/build/ M=$(CURDIR) modules_install
	test -f $(ETC_MODULES_FILE) || \
	  echo "# modules required by the T2-12 tile" > $(ETC_MODULES_FILE)
	grep rpmsg_pru_itcio $(ETC_MODULES_FILE) || echo rpmsg_pru_itcio >> $(ETC_MODULES_FILE)
	depmod


insmod:	all
	rmmod rpmsg_pru_itcio || exit 0
	insmod rpmsg_pru_itcio.ko

.PHONY:	FORCE
