SRCDIR:=src
LIBDIR:=$(SRCDIR)/rpmsg_lib/gen/
LIBFILE:=rpmsg_lib.lib
LIBPATH:=$(LIBDIR)/$(LIBFILE)

.PHONY:	build install clean check_bin

build:	check_bin
	make PRU_CGT=/usr/share/ti/cgt-pru -C src
	cp $(LIBPATH) .

clean:
	make PRU_CGT=/usr/share/ti/cgt-pru -C src clean
	rm -f $(LIBFILE)

check_bin:
	@mkdir -p /usr/share/ti/cgt-pru/bin || exit 99 ;\
	if [ ! -L /usr/share/ti/cgt-pru/bin/clpru ] ; then \
	  ln -s /usr/bin/clpru /usr/share/ti/cgt-pru/bin/clpru ;\
	  echo Linked /usr/bin/clpru to /usr/share/ti/cgt-pru/bin/clpru ;\
	fi




install:	build

