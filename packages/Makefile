PACKAGES+=emacs-nox
PACKAGES+=fbi
PACKAGES+=inotify-tools
PACKAGES+=git g++
PACKAGES+=software-properties-common python-software-properties

# For our (possible future) interactive services
PACKAGES+=libsystemd-dev
PACKAGES+=libpam-systemd

# For the debugging-perl-packet-daemon
PACKAGES+=libproc-daemon-perl

# For time parsing if we still end up needing that
PACKAGES+=libdatetime-format-strptime-perl 

# For FUSE if we end up using it
#PACKAGES+=fuse libfuse-dev

# For sdlsplash
PACKAGES+=libsdl1.2-dev libsdl-image1.2-dev libsdl-ttf2.0-dev
# NOTE WE ARE NOW REQUIRING ppa:ackley/mfm TO ALREADY BE IN THE REPOSITORIES!
# (SEE /root/T2-12-root-seed.sh FOR WHERE THAT SHOULD HAVE HAPPENED!)
PACKAGES+=ulam

# For building LKMs
PACKAGES+=strace
KERNEL_VERSION:=$(shell uname -r)
KERNEL_HEADERS_PKG:=linux-headers-$(KERNEL_VERSION) 
PACKAGES+=$(KERNEL_HEADERS_PKG)
FLAG_FILE:=.flagfile_INSTALL_COMPLETE

## Packages we can safely remove
REMOVE_PACKAGES+=doc-beaglebone-getting-started
REMOVE_PACKAGES+=doc-beaglebone-getting-started
REMOVE_PACKAGES+=doc-seeed-bbgw-getting-started

build:	FORCE
	@echo "PACKAGES: $(PACKAGES)"
	@echo "NOTE: Not doing 'apt-get update' -- do it yourself if you dare"

install:	build
	@if [ -f $(FLAG_FILE) ] ; then \
	  echo "NOTE: '$(FLAG_FILE)' detected; installation skipped" ; \
	else \
	  ping -c 1 -n google.com || (echo Need net to install packages) ; \
	  apt-get -y install $(PACKAGES) ; \
	  touch $(FLAG_FILE) ; \
	fi

clean:	FORCE
	rm -f *~

realclean:	clean
	rm -f $(FLAG_FILE)


.PHONY:	FORCE
