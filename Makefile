SHELL = /bin/bash
# 'packages' must install first, then pkgconfig
SUBDIRS:=packages pkgconfig lkms pru apps files services 
HOSTNAME:=$(shell uname -n)
HOSTMACH:=$(shell uname -m)
ON_TILE:=
#ifeq ($(HOSTNAME),T2-12)
ifeq ($(HOSTNAME),beaglebone)
ifeq ($(HOSTMACH),armv7l)
ON_TILE:=true
endif
endif

all:	$(SUBDIRS) 

touch:	$(SUBDIRS) 

clean:	$(SUBDIRS)

realclean:	clean $(SUBDIRS)

ifeq ($(ON_TILE),)
install:	
	$(error Must be on tile to install))

test:	FORCE
	$(error Must be on tile to test))
else
install:	$(SUBDIRS)

test:	FORCE
	$(MAKE) -C tests
endif

TAR_SWITCHES+=--exclude=tools --exclude=other --exclude=*~ --exclude=.git --exclude-backups
TAR_SWITCHES+=--exclude=doc/internal --exclude=doc/old-versions
TAR_SWITCHES+=--exclude=extra
TAR_SWITCHES+=--exclude=apps/cdm/cdm/cdmDEBUG --exclude=apps/cdm/cdm-hold

TAR_SWITCHES+=--mtime="2008-01-02 12:34:56"
TAR_SWITCHES+=--owner=0 --group=0 --numeric-owner 

REGNUM:=0
SLOTNUM:=02
cdmd:	FORCE
	MPWD=`pwd`;BASE=`basename $$MPWD`; \
	echo $$MPWD for $$BASE; \
	pushd ..;tar cvzf $$BASE-built.tgz $(TAR_SWITCHES) $$BASE; \
	cp -f $$BASE-built.tgz /home/debian/CDMSAVE/TGZS/; \
	FN=`/home/t2/MFM/bin/mfzmake cdmake $(REGNUM) $(SLOTNUM) $$BASE $$BASE-built.tgz | \
            perl -e "while(<>) {/'([^']+)'/ && print "'$$1}'`; \
	if [ "x$$FN" = "x" ] ; then echo "Build failed" ; else  \
	echo -n "Got $$FN for $$BASE, tag = "; \
	perl -e '"'$$FN'" =~ /[^-]+-[^-]+-([[:xdigit:]]+)[.]/; print $$1' > /cdm/tags/slot$(SLOTNUM)-install-tag.dat; \
	cat /cdm/tags/slot$(SLOTNUM)-install-tag.dat; \
	echo -n ", size = " ; stat -c %s $$FN; \
	cp -f $$FN /home/debian/CDMSAVE/CDMDS/; \
	fi; \
	popd

# Let's define a 'refresh' target -- a phony 'install light' -- to get
# around building the LKMs all the time.  Triggered by SC_REFRESH
refresh:	FORCE
	$(MAKE) -C apps/cdm install
	$(MAKE) -C apps/mfm install
	$(MAKE) -C files/opt install

restart:	FORCE
	pkill cdm.pl

$(SUBDIRS):	FORCE
	$(MAKE) -C $@ $(MAKECMDGOALS)

removeflagfiles:	FORCE
	find * -name ".flagfile*" -exec rm \{\} \;


.PHONY:	all clean realclean install test FORCE HOSTCHECK

