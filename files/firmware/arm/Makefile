FIRMWARE_BUILD_DIR:=$(shell uname -r | sed 's/\([0-9][0-9]*[.][0-9][0-9]*\)[^-]*-ti.*/\/opt\/source\/dtb-\1-ti/')
FIRMWARE_FILES_DIR:=$(FIRMWARE_BUILD_DIR)/src/arm
DTS_FILES:=$(wildcard *dts)
DTSI_FILES:=$(wildcard *dtsi)
DTB_FILES:=$(patsubst %.dts,$(FIRMWARE_FILES_DIR)/%.dtb,$(DTS_FILES))

all:	
	@echo $(DTS_FILES) / $(DTB_FILES)

touch:	FORCE
	touch $(DTS_FILES) $(DTSI_FILES)

install:	install_dtbs

$(DTBO_FILE):	$(CAPE_FILE)
	/usr/bin/dtc -W no-unit_address_vs_reg $^ -o $@

install_dtbs:	$(DTB_FILES) 

$(FIRMWARE_FILES_DIR)/%.dtb:	%.dts $(DTSI_FILES)
	cp $^ $(FIRMWARE_FILES_DIR) || (echo Must be root ; exit 2)
	cd $(FIRMWARE_BUILD_DIR) ; make DTC=/usr/bin/dtc DTC_FLAGS="-W no-unit_address_vs_reg" install

clean:	FORCE
	rm -f *~ $(FIRMWARE_FILES_DIR)/*~ $(FIRMWARE_FILES_DIR)/.*.cmd $(FIRMWARE_FILES_DIR)/.*.d $(FIRMWARE_FILES_DIR)/.*.tmp $(DTBO_FILE)  

realclean:	clean
	rm -f $(DTB_FILES) $(INSTALLED_DTBO_FILE) 
	#cd $(FIRMWARE_BUILD_DIR) ; make DTC=/usr/bin/dtc clean

.PHONY:	all clean realclean install FORCE

