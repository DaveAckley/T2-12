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


.PHONY: all
all:
	@make -C $(KDIR) M=$(CURDIR) modules

.PHONY: clean
clean:
	@make -C $(KDIR) M=$(CURDIR) clean

.PHONY:	install
install:	all
	rmmod rpmsg_pru_itcio || exit 0
	insmod rpmsg_pru_itcio.ko
