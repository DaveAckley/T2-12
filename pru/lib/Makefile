SRCDIR:=src
LIBDIR:=$(SRCDIR)/rpmsg_lib/gen/
LIBFILE:=rpmsg_lib.lib
LIBPATH:=$(LIBDIR)/$(LIBFILE)

.PHONY:	build install clean

build:
	make PRU_CGT=/usr/share/ti/cgt-pru -C src
	cp $(LIBPATH) .

clean:
	make PRU_CGT=/usr/share/ti/cgt-pru -C src clean
	rm -f $(LIBFILE)


install:	build

