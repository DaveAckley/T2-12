PACKAGES+=emacs-nox
PACKAGES+=fbi
PACKAGES+=inotify-tools
PACKAGES+=git g++
PACKAGES+=software-properties-common python-software-properties
# For sdlsplash
PACKAGES+=libsdl1.2-dev libsdl-image1.2-dev libsdl-ttf2.0-dev
# NOTE WE ARE NOW REQUIRING ppa:ackley/mfm TO ALREADY BE IN THE REPOSITORIES!
# (SEE /root/T2-12-root-seed.sh FOR WHERE THAT SHOULD HAVE HAPPENED!)
PACKAGES+=ulam

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
