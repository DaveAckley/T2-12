PACKAGES+=emacs-nox
PACKAGES+=fbi
PACKAGES+=inotify-tools
PACKAGES+=git g++
PACKAGES+=software-properties-common 
PACKAGES+=libncurses-dev

# For unpacking .mfz files in emacs
PACKAGES+=zip

# For CDM crypto checking
PACKAGES+=libcrypt-openssl-rsa-perl

# Generally useful framebuffer manager?
PACKAGES+=fbset

# For last-ditch file transfers
PACKAGES+=lrzsz

# Prereqs for Graphics::FrameBuffer if we end up using it (which we are currently trying to)
PACKAGES+=libinline-perl libimager-perl libmath-bezier-perl libmath-gradient-perl libtest-most-perl

# also some fonts:
PACKAGES+=fonts-freefont-ttf
#jessie doesn't have: libfile-map-perl libperlio-layers-perl ??
# For home-building File::Map
PACKAGES+=libtest-fatal-perl libtest-warnings-perl

# For our (possible future) interactive services
PACKAGES+=libsystemd-dev
PACKAGES+=libpam-systemd

# For the debugging-perl-packet-daemon
PACKAGES+=libproc-daemon-perl

# For time parsing if we still end up needing that
PACKAGES+=libdatetime-format-strptime-perl 

# For FUSE if we end up using it
#PACKAGES+=fuse libfuse-dev

# For Perl SDL if we end up using it
# 201906240416 Now believing we will not be using it
#PACKAGES+=libalien-sdl-perl libmodule-build-perl

# In Debian Buster apparently the tslib packages once again exist
# So let's try not building it ourselves
## For building tslib
#PACKAGES+=cmake
PACKAGES+=libts-dev libts-bin

### HANDLE SDL PACKAGES SEPARATELY SINCE WE'RE GRR BUILDING IT
# SEE ../extra/Makefile FOR DETAILS
# For sdlsplash
#SDL_BASE_PACKAGES+=libsdl1.2-dev libsdl1.2debian
#SDL_EXTRA_PACKAGES+=libsdl-image1.2-dev libsdl-ttf2.0-dev

# NOTE WE ARE NOW REQUIRING ppa:ackley/mfm TO ALREADY BE IN THE REPOSITORIES!
# (SEE /root/T2-12-root-seed.sh FOR WHERE THAT SHOULD HAVE HAPPENED!)
# 201912022047 NOT USING MFM OR ULAM from packages ATM
# PACKAGES+=ulam

# For building LKMs
PACKAGES+=strace
KERNEL_VERSION:=$(shell uname -r)
KERNEL_HEADERS_PKG:=linux-headers-$(KERNEL_VERSION) 
PACKAGES+=$(KERNEL_HEADERS_PKG)
FLAG_FILE:=.flagfile_INSTALL_COMPLETE
REMOVE_FLAG_FILE:=.flagfile_REMOVE_COMPLETE

## Packages we can (hopefully safely) remove
#  WARNING YOU CANNOT RELY ON KERNEL_VERSION WHEN 'make preremove' IS RUN!
REMOVE_PACKAGES+=bb-bbai-firmware
REMOVE_PACKAGES+=bb-node-red-installer
REMOVE_PACKAGES+=bone101
REMOVE_PACKAGES+=bonescript
REMOVE_PACKAGES+=c9-core-installer
REMOVE_PACKAGES+=doc-beaglebone-getting-started
REMOVE_PACKAGES+=rfkill
REMOVE_PACKAGES+=ardupilot-copter-3.6-blue ardupilot-copter-3.6-pocket ardupilot-rover-3.4-bbbmini ardupilot-rover-3.4-blue ardupilot-rover-3.4-pocket
REMOVE_PACKAGES+=libbluray2
#REMOVE_PACKAGES+=ti-open-cl

UNHOLD_PACKAGES+=c9-core-installer

build:	FORCE
	@echo "PACKAGES: $(PACKAGES)"
	@echo "NOTE: Not doing 'apt-get update' -- do it yourself if you dare"

install:	build preremove
	@if [ -f $(FLAG_FILE) ] ; then \
	  echo "NOTE: '$(FLAG_FILE)' detected; installation skipped" ; \
	else \
	  ping -c 1 -n google.com || (echo Need net to install packages) ; \
	  apt-get -y install $(PACKAGES) ; \
	  touch $(FLAG_FILE) ; \
	fi

preremove:	FORCE
	@if [ -f $(REMOVE_FLAG_FILE) ] ; then \
	  echo "NOTE: '$(REMOVE_FLAG_FILE)' detected; preremoval skipped" ; \
	else \
	  echo "PREREMOVING PACKAGES TO SAVE SPACE" ; \
	  ping -c 1 -n google.com || (echo Want net when removing packages...um why) ; \
	  apt-mark unhold $(UNHOLD_PACKAGES) ; \
	  apt-get -y remove --purge $(REMOVE_PACKAGES) ; \
	  apt -y autoremove ; \
	  touch $(REMOVE_FLAG_FILE) ; \
	fi


clean:	FORCE
	rm -f *~

realclean:	clean
	rm -f $(FLAG_FILE)


.PHONY:	FORCE
