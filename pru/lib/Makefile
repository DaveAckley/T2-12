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
	@if [ ! -L /usr/share/ti/cgt-pru/bin ] ; then \
	  ln -s /usr/bin /usr/share/ti/cgt-pru/bin ;\
	  echo Linked /usr/bin to /usr/share/ti/cgt-pru/bin ;\
	fi ;\
	done

install:	build

