SHELL = /bin/bash
HOSTNAME:=$(shell uname -n)
HOSTMACH:=$(shell uname -m)
ON_TILE:=
ifeq ($(HOSTNAME),beaglebone)
ifeq ($(HOSTMACH),armv7l)
ON_TILE:=true
endif
endif
ON_TILE:=1
# We only make sense on the tile
ifeq ($(ON_TILE),)
$(error Must be running on the T2 tile)
endif

# Deal with subdirs in this order precisely:
SUBDIRS:=base low cdm mfm

all clean cdmd realclean:	$(SUBDIRS)

realclean:	clean

clean:	FORCE
	rm -f *~

$(SUBDIRS):	FORCE
	$(MAKE) -C $@ $(MAKECMDGOALS)

.PHONY:	all clean realclean install test FORCE 
