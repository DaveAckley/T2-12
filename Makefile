SUBDIRS:=files apps
HOSTNAME:=$(shell uname -n)
HOSTMACH:=$(shell uname -m)
ON_TILE:=
ifeq ($(HOSTNAME),T2-12)
ifeq ($(HOSTMACH),armv7l)
ON_TILE:=true
endif
endif

all:	$(SUBDIRS) 

clean:	$(SUBDIRS)

realclean:	clean $(SUBDIRS)

ifeq ($(ON_TILE),)
install:	
	$(error Must be on tile to install))
else
install:	$(SUBDIRS)
endif

$(SUBDIRS):	FORCE
	$(MAKE) -C $@ $(MAKECMDGOALS)

.PHONY:	all clean realclean install FORCE HOSTCHECK

