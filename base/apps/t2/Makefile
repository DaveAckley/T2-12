CMDS:=build touch install clean realclean
$(CMDS):	FORCE

build:
	gcc bus-service.c -o bus-service `pkg-config --cflags --libs libsystemd`

touch:
	@echo '(touch target not yet implemented)'

install: 
	@echo '(install target not yet implemented)'

clean:	
	rm -f *~

realclean:	clean

.PHONY:	FORCE


