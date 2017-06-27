INPUT:=boot-config-pin.txt
OUTPUT_DIR:=/opt/scripts/t2
OUTPUT_FILE:=$(OUTPUT_DIR)/

all:	FORCE
	@ls -l $(INPUT)

touch:	FORCE
	touch $(INPUT)

clean:	FORCE
	@rm -f *~

realclean:	clean touch

install:	$(OUTPUT_FILE)

$(OUTPUT_FILE):	$(INPUT)
	mkdir -p $(OUTPUT_DIR) || (echo Must be root ; exit 2)
	cp $< $@ || (echo Must be root ; exit 2)

.PHONY:	FORCE
