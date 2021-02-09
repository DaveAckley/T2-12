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

APP_NAME:=cdm.sh
DEST_DIR:=/opt/scripts/t2
DEST_PATH:=$(DEST_DIR)/$(APP_NAME)
ENGINE_NAME:=cdm.pl
SRC_FILES:=$(wildcard cdm/*.pm cdm/*.pl cdm/mfzrun)
OBJ_DEST_DIR:=/opt/scripts/t2/cdm
OBJS:=$(OBJ_DEST_DIR)/$(SRC_FILES)

#DEFAULT TARGET
all:	build

#############
##CDMD CREATION
BASE:=$(lastword $(subst /, ,$(dir $(realpath $(firstword $(MAKEFILE_LIST))))))
TAR_FILE:=$(BASE)-built.tgz
TAR_FILE_DIR:=..
TAR_PATH:=$(abspath $(TAR_FILE_DIR)/$(TAR_FILE))

TAR_SWITCHES+=--exclude=--exclude=*~ --exclude=.git --exclude-backups

TAR_SWITCHES+=--mtime="2008-01-02 12:34:56"
TAR_SWITCHES+=--owner=0 --group=0 --numeric-owner 

REGNUM:=0
SLOTNUM:=07
DESTDIR:=$(abspath ..)
TAG_PATH:=$(DESTDIR)/slot$(SLOTNUM)-install-tag.dat

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
	echo "  cp $(TAG_PATH) /cdm/tags ; cp $(DESTDIR)/$$FN /cdm/common"; \
	fi; \
	popd
##CDMD CREATION
#############

run:	build
	./$(APP_NAME)

restart:
	killall $(ENGINE_NAME)

build:	cdm/mfzrun $(APP_NAME)

# Copy mfzrun so cdm can do .mfz ops without the MFM tree
cdm/mfzrun:	/home/t2/MFM/bin/mfzrun
	cp $^ $@

$(APP_NAME):	FORCE
	chmod a+rx $(APP_NAME)
	@echo $(APP_NAME) ready

#touch:	FORCE
#	touch $(APP_NAME)

install: $(APP_NAME) $(OBJ_DEST_DIR)
	mkdir -p $(DEST_DIR)
	@unlink $(DEST_PATH) 2>/dev/null || echo no existing $(DEST_PATH) to unlink
	cp $< $(DEST_DIR) || (echo status=$$?, must be root? ; exit 2)

$(OBJ_DEST_DIR):	FORCE
	mkdir -p $(OBJ_DEST_DIR)
	cp -p $(SRC_FILES) $@

clean:	
	rm -f *~ cdm/*~

realclean:	clean
	rm -rf $(OBJ_DEST_DIR)
	rm -f $(TAR_PATH)

.PHONY:	all clean realclean install test FORCE 
