APP_NAME:=t2serloop.py
DRIVER_NAME:=t2serloopRunner.sh
EXE_NAMES:=$(APP_NAME) $(DRIVER_NAME)
PKG_NAMES:=PacketIO.py Utils.py
SRCS:=$(EXE_NAMES) $(PKG_NAMES)

CMDS:=build touch install clean realclean
$(CMDS):	FORCE

run:	build
	./$(APP_NAME) 

build:	$(APP_NAME) $(DRIVER_NAME)

$(EXE_NAMES):	FORCE
	chmod a+rx $@

touch:	FORCE
	touch $(SRCS)

install: touch $(SRCS)
	mkdir -p /opt/scripts/t2
	cp $(SRCS) /opt/scripts/t2/ || (echo must be root ; exit 2)

clean:	
	rm -f *~

realclean:	clean

.PHONY:	FORCE


