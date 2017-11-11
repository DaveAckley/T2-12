obj-m+=t2lock.o

all:	t2lock.ko testt2lock

t2lock.ko:	t2lock.c Makefile
	make -C /lib/modules/$(shell uname -r)/build/ M=$(CURDIR) modules

testt2lock:	testt2lock.c
	$(CC) -c testt2lock.c -o testt2lock

clean:	uninstall
	make -C /lib/modules/$(shell uname -r)/build/ M=$(CURDIR) clean
	rm -f test2lock *.o *~

install:	all uninstall
	echo insmod t2lock.ko

uninstall:
	echo rmmod t2lock 2>/dev/null || exit 0
