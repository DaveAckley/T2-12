#
# Makefile written by Zubeen Tolani <ZeekHuge - zeekhuge@gmail.com>
# Copyright (C) 2016 Zubeen Tolani <ZeekHuge - zeekhuge@gmail.com>

# Modified by ackley@ackleyshack.com 2017.  See copyright info in
# rpmsg_pru_itcio.c in this directory.

#
# Makefile to compile itc_pkt.c
#

MNAME:=itc_pkt
obj-m += $(MNAME).o

KDIR?=/lib/modules/$(shell uname -r)/build

ETC_MODULES_FILE:=/etc/modules-load.d/t2_12_modules.conf

all:	FORCE
	@make -C $(KDIR) M=$(CURDIR) modules

clean:	FORCE
	@make -C $(KDIR) M=$(CURDIR) clean

install:	install_files

install_files:	all
	make INSTALL_MOD_DIR=itc -C /lib/modules/4.4.54-ti-r93/build/ M=$(CURDIR) modules_install
	test -f $(ETC_MODULES_FILE) || \
	  echo "# modules required by the T2-12 tile" > $(ETC_MODULES_FILE)
	grep $(MNAME) $(ETC_MODULES_FILE) || echo $(MNAME) >> $(ETC_MODULES_FILE)
	grep cmemk $(ETC_MODULES_FILE) || echo cmemk >> $(ETC_MODULES_FILE)
	depmod


insmod:	install_files
	modprobe -r $(MNAME) || exit 0
	modprobe -r pru_rproc || exit 0
	modprobe pru_rproc || exit 0
	modprobe $(MNAME)

.PHONY:	FORCE
