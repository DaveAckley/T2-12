TARGET=itc
obj-m+= $(TARGET).o
itc-objs+=itcinit.o itcimpl.o

all:	itc.ko testitc

itc.ko:	itcinit.c itcimpl.c Makefile
	make -C /lib/modules/$(shell uname -r)/build/ M=$(PWD) modules

testitc:	testitc.c Makefile
	$(CC) testitc.c -o testitc

clean:	uninstall
	make -C /lib/modules/$(shell uname -r)/build/ M=$(PWD) clean
	rm -f testitc *.o *~

install:	all uninstall
	sudo insmod itc.ko

uninstall:
	rmmod itc 2>/dev/null || exit 0
