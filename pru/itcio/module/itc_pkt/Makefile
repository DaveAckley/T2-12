#
# Makefile written by Zubeen Tolani <ZeekHuge - zeekhuge@gmail.com>
# Copyright (C) 2016 Zubeen Tolani <ZeekHuge - zeekhuge@gmail.com>

# Modified by ackley@ackleyshack.com 2017-2017.  See copyright info in
# itc_pkt.c in this directory.

#
# Makefile to compile itc_pkt.c
#

MNAME:=itc_pkt

KDIR?=/lib/modules/$(shell uname -r)/build

ETC_MODULES_FILE:=/etc/modules-load.d/t2_12_modules.conf

BUF_DIR:=../../common
BUF_SRC_FILENAMES:=PacketBuffer.c SharedState.c ITCIterator.c
BUF_HDR_FILENAMES:=$(patsubst %.c, %.h, $(BUF_SRC_FILENAMES))
BUF_SRC_ORIGIN_FILES:=$(patsubst %, $(BUF_DIR)/%, $(BUF_SRC_FILENAMES))
BUF_HDR_ORIGIN_FILES:=$(patsubst %, $(BUF_DIR)/%, $(BUF_HDR_FILENAMES))
BUF_ORIGIN_FILES:=$(BUF_SRC_ORIGIN_FILES) $(BUF_HDR_ORIGIN_FILES)
BUF_OBJ_FILENAMES:=$(patsubst %.c, %.o, $(BUF_SRC_FILENAMES))

obj-m += $(MNAME).o

itc_pkt-objs := module.o $(BUF_OBJ_FILENAMES)

all:	copy_common
	@make -C $(KDIR) M=$(CURDIR) modules

clean:	FORCE
	@make -C $(KDIR) M=$(CURDIR) clean


copy_common:	FORCE
	cp -f $(BUF_ORIGIN_FILES) .

install:	install_files insmod

install_files:	all
	make INSTALL_MOD_DIR=itc -C /lib/modules/4.4.54-ti-r93/build/ M=$(CURDIR) modules_install
	test -f $(ETC_MODULES_FILE) || \
	  echo "# modules required by the T2-12 tile" > $(ETC_MODULES_FILE)
	grep $(MNAME) $(ETC_MODULES_FILE) || echo $(MNAME) >> $(ETC_MODULES_FILE)
	depmod


insmod:	FORCE
	modprobe -r $(MNAME) || exit 0
	modprobe -r pru_rproc || exit 0
	modprobe pru_rproc || exit 0
	modprobe $(MNAME)

.PHONY:	FORCE
