INPUTS:=boot-config-pin.txt t2-startup.sh t2-splash.sh
OUTPUT_DIR:=/opt/scripts/t2
OUTPUT_FILE:=$(OUTPUT_DIR)/
OUTPUTS:=$(patsubst %,$(OUTPUT_DIR)/%,$(INPUTS))
SERVICE_FILES:=$(wildcard *.service)
SERVICE_DIR:=/lib/systemd/system
SERVICE_OUTPUTS:=$(patsubst %,$(SERVICE_DIR)/%,$(SERVICE_FILES))
SERVICE_PATH:=$(SERVICE_DIR)/$(SERVICE_FILE)
SPLASH_PNG_IN:=MFM-T2-10.png
SPLASH_PNG_OUT:=$(OUTPUT_DIR)/t2-splash.png

all:	FORCE
	@ls -l $(INPUTS)

touch:	FORCE
	touch $(INPUTS)

clean:	FORCE
	@rm -f *~

realclean:	clean touch

install:	$(OUTPUT_DIR) $(OUTPUTS) $(SERVICE_OUTPUTS) $(SPLASH_PNG_OUT)

$(OUTPUT_DIR)/%:	%
	mkdir -p $(OUTPUT_DIR) || (echo Must be root ; exit 2)
	cp $^ $@ || (echo Must be root ; exit 2)

$(SPLASH_PNG_OUT):	$(SPLASH_PNG_IN) $(OUTPUT_DIR)
	cp $< $@ || (echo Must be root ; exit 2)

$(SERVICE_DIR)/%:	%
	cp $< $@ || (echo Must be root ; exit 2)
	systemctl daemon-reload
	systemctl enable $<

.PHONY:	FORCE
