APP_NAME:=cdm.sh
DEST_DIR:=/opt/scripts/t2
DEST_PATH:=$(DEST_DIR)/$(APP_NAME)
SRC_FILES:=$(wildcard cdm/*.pm cdm/*.pl cdm/mfzrun)
OBJ_DEST_DIR:=/opt/scripts/t2/cdm
OBJS:=$(OBJ_DEST_DIR)/$(SRC_FILES)

CMDS:=build touch install clean realclean

$(CMDS):	FORCE

run:	build
	./$(APP_NAME)

build:	cdm/mfzrun $(APP_NAME)

# Copy mfzrun so cdm can do .mfz ops without the MFM tree
cdm/mfzrun:	/home/t2/MFM/bin/mfzrun
	cp $^ $@

$(APP_NAME):	FORCE
	chmod a+rx $(APP_NAME)
	@echo $(APP_NAME) ready

touch:	FORCE
	touch $(APP_NAME)

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

.PHONY:	FORCE


