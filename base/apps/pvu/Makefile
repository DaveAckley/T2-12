APP_NAME:=pvu.pl
SRCS:=$(APP_NAME)

CMDS:=build touch install clean realclean
$(CMDS):	FORCE

run:	build
	./$(APP_NAME) 

build:	$(APP_NAME)

$(APP_NAME):	
	chmod a+rx $(APP_NAME)

touch:	FORCE
	touch $(SRCS)

install: $(APP_NAME)
	mkdir -p /opt/scripts/t2
	cp $< /opt/scripts/t2/ || (echo must be root ; exit 2)

clean:	
	rm -f *~

realclean:	clean

.PHONY:	FORCE


