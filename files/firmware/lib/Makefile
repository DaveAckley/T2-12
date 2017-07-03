OVERLAY_FILES:=$(wildcard *-00A0.dts)
INSTALL_DIR:=/lib/firmware
DTBO_FILES:=$(patsubst %.dts,%.dtbo,$(OVERLAY_FILES))
INSTALLED_DTBO_FILES:=$(patsubst %,$(INSTALL_DIR)/%,$(DTBO_FILES))

all:	$(DTBO_FILES)

touch:	FORCE
	touch $(OVERLAY_FILES)

%.dtbo:	%.dts 
	/usr/bin/dtc $< -o $@

$(INSTALL_DIR)/%.dtbo:	%.dtbo
	cp $^ $@ || (echo Must be root ; exit 2)

install:	$(INSTALLED_DTBO_FILES)

clean:	FORCE
	rm -f $(DTBO_FILES)
	rm -f *~ 

realclean:	clean
	rm -f  $(INSTALLED_DTBO_FILES) 

.PHONY:	all clean realclean install FORCE

