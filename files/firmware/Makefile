FIRMWARE_BUILD_DIR:=/opt/source/dtb-4.4-ti
FIRMWARE_FILES_DIR:=$(FIRMWARE_BUILD_DIR)/src/arm
DTS_FILES:=$(wildcard *dts)
DTSI_FILES:=$(wildcard *dtsi)
DTB_FILES:=$(patsubst %.dts,$(FIRMWARE_FILES_DIR)/%.dtb,$(DTS_FILES))
CAPE_FILE:=cape-universal2-00A0.dts
DTBO_FILE:=cape-universal2-00A0.dtbo
DTBO_FILES_DIR:=/lib/firmware
INSTALLED_DTBO_FILE:=$(DTBO_FILES_DIR)/$(DTBO_FILE)

all:	cape
	@echo $(DTS_FILES) / $(DTB_FILES) / $(CAPE_FILE)

touch:	FORCE
	touch $(DTS_FILES) $(DTSI_FILES) $(CAPE_FILE)

install:	$(DTBO_FILE) install_dtbs
	cp $< $(INSTALLED_DTBO_FILE) || (echo Must be root ; exit 2)

cape:	$(DTBO_FILE)

$(DTBO_FILE):	$(CAPE_FILE)
	/usr/bin/dtc $^ -o $@

install_dtbs:	$(DTB_FILES) 

$(FIRMWARE_FILES_DIR)/%.dtb:	%.dts $(DTSI_FILES)
	cp $^ $(FIRMWARE_FILES_DIR) || (echo Must be root ; exit 2)
	cd $(FIRMWARE_BUILD_DIR) ; make DTC=/usr/bin/dtc install

clean:	FORCE
	rm -f *~ $(FIRMWARE_FILES_DIR)/*~ $(FIRMWARE_FILES_DIR)/.*.cmd $(FIRMWARE_FILES_DIR)/.*.d $(FIRMWARE_FILES_DIR)/.*.tmp $(DTBO_FILE)  

realclean:	clean
	rm -f $(DTB_FILES) $(INSTALLED_DTBO_FILE) 
	#cd $(FIRMWARE_BUILD_DIR) ; make DTC=/usr/bin/dtc clean

.PHONY:	all clean realclean install FORCE

