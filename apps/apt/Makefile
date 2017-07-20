PACKAGES+=emacs-nox
PACKAGES+=fbi
PACKAGES+=inotify-tools
PACKAGES+=git g++
PACKAGES+=libsdl1.2-dev libsdl-image1.2-dev libsdl-ttf2.0-dev
PACKAGES+=libcrypt-openssl-bignum-perl libcrypt-openssl-rsa-perl libcapture-tiny-perl
PACKAGES+=software-properties-common python-software-properties

FLAG_FILE:=.flagfile_INSTALL_COMPLETE

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
