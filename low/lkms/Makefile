APPS:=$(shell find . -type d -a ! -name ".*" -a ! -name "include" -a ! -path "*/*/*")

CMDS:=build install clean realclean touch

$(CMDS):	$(APPS)


$(APPS):	FORCE
	@echo NOT RUNNING 'make -C $@ $(MAKECMDGOALS)' BECAUSE WE DO NOT USE IT RIGHT

.PHONY:	FORCE
