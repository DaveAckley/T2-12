###### Mon Feb  8 00:49:18 2021 
## THIS IS A TRANSITIONAL MAKEFILE TO BUILD THE
## (SOON-TO-BE DEPRECATED) cdmss-02-ffffff.mfz

SHELL = /bin/bash
HOSTNAME:=$(shell uname -n)
HOSTMACH:=$(shell uname -m)
ON_TILE:=
#ifeq ($(HOSTNAME),T2-12)
ifeq ($(HOSTNAME),beaglebone)
ifeq ($(HOSTMACH),armv7l)
ON_TILE:=true
endif
endif

warning:	FORCE
	@echo ONLY make cdmd EXISTS FOR THIS MAKEFILE -- USE CAREFULLY
	@exit 1

#############
##CDMD CREATION
BASE:=$(lastword $(subst /, ,$(dir $(realpath $(firstword $(MAKEFILE_LIST))))))
TAR_FILE:=$(BASE)-built.tgz
TAR_FILE_DIR:=..
TAR_PATH:=$(abspath $(TAR_FILE_DIR)/$(TAR_FILE))

TAR_SWITCHES+=--exclude=tools --exclude=*~ --exclude=.git --exclude-backups
TAR_SWITCHES+=--exclude=doc/internal --exclude=doc/old-versions
TAR_SWITCHES+=--exclude=extra other

TAR_SWITCHES+=--mtime="2008-01-02 12:34:56"
TAR_SWITCHES+=--owner=0 --group=0 --numeric-owner 


REGNUM:=0
SLOTNUM:=02
TAG_PATH:=/home/t2/slot$(SLOTNUM)-install-tag.dat

$(TAR_PATH):	FORCE
	pushd ..;tar cvzf $(TAR_PATH) $(TAR_SWITCHES) $(BASE);popd

cdmd:	$(TAR_PATH)
	pushd .. ; \
	FN=`/home/t2/MFM/bin/mfzmake cdmake $(REGNUM) $(SLOTNUM) $(BASE) $(BASE)-built.tgz | \
            perl -e "while(<>) {/'([^']+)'/ && print "'$$1}'`; \
	if [ "x$$FN" = "x" ] ; then echo "Build failed" ; else  \
	echo -n "Got $$FN for $(BASE), tag = "; \
	perl -e '"'$$FN'" =~ /[^-]+-[^-]+-([[:xdigit:]]+)[.]/; print $$1' > $(TAG_PATH); \
	cat $(TAG_PATH); \
	echo -n ", size = " ; stat -c %s $$FN; \
	echo "TO RELEASE:" ; \
	echo "# cp $(TAG_PATH) /cdm/tags"; \
	echo "# mv $$FN /cdm/common"; \
	fi; \
	popd

.PHONY:	FORCE

