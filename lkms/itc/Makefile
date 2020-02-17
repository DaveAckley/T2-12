TARGET=itc
obj-m+= $(TARGET).o
#itc-objs+=itcinit.o itcimpl.o

EXTRA_CFLAGS := -I$(src)/../include

MODULES_DIR:=/lib/modules/$(shell uname -r)
MODULES_BUILD_DIR:=$(MODULES_DIR)/build
MODULES_OUTPUT_DIR:=$(MODULES_DIR)/kernel/drivers/$(TARGET)

ETC_MODULES_FILE:=/etc/modules-load.d/t2_12_modules.conf

all:	itc.ko testitc

itc.ko:	itc.c itc.c $(wildcard *.h) Makefile
	make -C /lib/modules/$(shell uname -r)/build/ M=$(CURDIR) modules

testitc:	testitc.c Makefile
	$(CC) -Wall -pedantic -ansi -Werror testitc.c -o testitc

clean:	FORCE
	make -C /lib/modules/$(shell uname -r)/build/ M=$(CURDIR) clean
	rm -f testitc *.o *~

insmod:	all rmmod
	sudo insmod itc.ko

rmmod:
	rmmod itc 2>/dev/null || exit 0

install:	install_files 

install_files:	all
	make INSTALL_MOD_DIR=itc -C $(MODULES_BUILD_DIR) M=$(CURDIR) modules_install
	@test -f $(ETC_MODULES_FILE) || \
	  echo "# modules required by the T2-12 tile" > $(ETC_MODULES_FILE)
	grep itc $(ETC_MODULES_FILE) || echo itc >> $(ETC_MODULES_FILE)
	depmod

uninstall:	FORCE
	@echo "WRITE ME" && exit 1



.PHONY:	FORCE
