APP_NAME:=cdm.sh
DEST_DIR:=/opt/scripts/t2
DEST_PATH:=$(DEST_DIR)/$(APP_NAME)

CMDS:=build touch install clean realclean

$(CMDS):	FORCE

run:	build
	./$(APP_NAME)

build:	$(APP_NAME)

$(APP_NAME):	FORCE
	chmod a+rx $(APP_NAME)
	@echo $(APP_NAME) ready

touch:	FORCE
	touch $(APP_NAME)

install: $(APP_NAME)
	mkdir -p $(DEST_DIR)
	@unlink $(DEST_PATH) 2>/dev/null || echo no existing $(DEST_PATH) to unlink
	cp $< $(DEST_DIR) || (echo status=$$?, must be root? ; exit 2)

clean:	
	rm -f *~

realclean:	clean

.PHONY:	FORCE


