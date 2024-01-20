APP_NAME:=t2serloop.py
DRIVER_NAME:=t2serloopRunner.sh
PKG_NAMES:=PacketIO.py
SRCS:=$(APP_NAME) $(DRIVER_NAME) $(PKG_NAMES)

CMDS:=build touch install clean realclean
$(CMDS):	FORCE

run:	build
	./$(APP_NAME) 

build:	$(APP_NAME) $(DRIVER_NAME)

$(APP_NAME):	
	chmod a+rx $(APP_NAME)

$(DRIVER_NAME):	
	chmod a+rx $(DRIVER_NAME)

touch:	FORCE
	touch $(SRCS)

install: $(SRCS)
	mkdir -p /opt/scripts/t2
	cp $^ /opt/scripts/t2/ || (echo must be root ; exit 2)

clean:	
	rm -f *~

realclean:	clean

.PHONY:	FORCE


