INPUTS:=boot-config-pin.txt t2-startup.sh
OUTPUT_DIR:=/opt/scripts/t2
OUTPUT_FILE:=$(OUTPUT_DIR)/
SERVICE_FILE:=t2-startup.service
SERVICE_DIR:=/lib/systemd/system
SERVICE_PATH:=$(SERVICE_DIR)/$(SERVICE_FILE)

all:	FORCE
	@ls -l $(INPUTS)

touch:	FORCE
	touch $(INPUTS)

clean:	FORCE
	@rm -f *~

realclean:	clean touch

install:	$(OUTPUT_DIR) $(SERVICE_PATH)

$(OUTPUT_DIR):	$(INPUTS)
	mkdir -p $(OUTPUT_DIR) || (echo Must be root ; exit 2)
	cp $^ $@ || (echo Must be root ; exit 2)

$(SERVICE_PATH):	$(SERVICE_FILE)
	mkdir -p $(SERVICE_DIR) || (echo Must be root ; exit 2)
	cp $< $@ || (echo Must be root ; exit 2)

.PHONY:	FORCE
