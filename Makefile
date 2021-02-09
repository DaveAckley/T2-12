SHELL = /bin/bash
HOSTNAME:=$(shell uname -n)
HOSTMACH:=$(shell uname -m)
ON_TILE:=
ifeq ($(HOSTNAME),beaglebone)
ifeq ($(HOSTMACH),armv7l)
ON_TILE:=true
endif
endif
# We only make sense on the tile
ifeq ($(ON_TILE),)
$(error Must be running on the T2 tile)
endif

# Deal with subdirs in this order precisely:
SUBDIRS:=base low cdm mfm

all install clean realclean:	$(SUBDIRS)

realclean:	clean

cdmd:	FORCE
	@echo "  Do 'make cdmd' as desired in subdirs: $(SUBDIRS)"
	@exit 1

clean:	FORCE
	rm -f *~

$(SUBDIRS):	FORCE
	$(MAKE) -C $@ $(MAKECMDGOALS)

.PHONY:	all clean realclean cdmd install test FORCE 
