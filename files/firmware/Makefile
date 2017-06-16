FIRMWARE_BUILD_DIR:=/opt/source/dtb-4.4-ti
FIRMWARE_FILES_DIR:=$(FIRMWARE_BUILD_DIR)/src/arm
DTS_FILES:=$(wildcard *dts)
DTB_FILES:=$(patsubst %.dts,$(FIRMWARE_FILES_DIR)/%.dtb,$(DTS_FILES))

all:
	@echo $(DTS_FILES) / $(DTB_FILES)

install:	$(DTB_FILES) 

$(FIRMWARE_FILES_DIR)/%.dtb:	%.dts
	cp $^ $(FIRMWARE_FILES_DIR) || (echo Must be root ; exit 2)
	cd $(FIRMWARE_BUILD_DIR) ; make DTC=/usr/bin/dtc install


clean:	FORCE
	rm *~

realclean:	clean
	rm *.dtb

.PHONY:	all clean realclean install FORCE

