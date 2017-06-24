all:	spidev_test


spidev_test:	spidev_test.c
	gcc -Wall -g2 $< -o $@

clean:	FORCE
	rm *~

realclean:	clean
	rm spidev_test

.PHONY:	FORCE
