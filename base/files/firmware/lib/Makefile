OVERLAY_FILES:=$(wildcard *-00A0.dts)
INSTALL_DIR:=/opt/source/bb.org-overlays/src/arm
MAKE_DIR_FOR_INSTALL_DIR:=
DTBO_FILES:=$(patsubst %.dts,%.dtbo,$(OVERLAY_FILES))
INSTALLED_DTBO_FILES:=$(patsubst %,$(INSTALL_DIR)/%,$(DTBO_FILES))
INSTALLED_DTS_FILES_FOR_THE_RECORD:=$(patsubst %,$(INSTALL_DIR)/%,$(OVERLAY_FILES))

all:	FORCE
	echo Only 'make install' does anything in this directory

touch:	FORCE
	touch $(OVERLAY_FILES)

$(INSTALL_DIR)/%.dtbo:	$(INSTALL_DIR)/%.dts
	make -C /opt/source/bb.org-overlays 

$(INSTALLED_DTS_FILES_FOR_THE_RECORD):	$(OVERLAY_FILES)
	cp $(OVERLAY_FILES) $(INSTALL_DIR) || (echo Must be root ; exit 2)

install:	$(INSTALLED_DTBO_FILES)
	make -C /opt/source/bb.org-overlays install

clean:	FORCE
	rm -f $(DTBO_FILES)
	rm -f *~ 

realclean:	clean
	rm -f  $(INSTALLED_DTBO_FILES) 

.PHONY:	all clean realclean install FORCE

