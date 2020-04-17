APPS:=$(shell find . -type d -a ! -name ".*" -a ! -name "include" -a ! -path "*/*/*")

CMDS:=build install clean realclean touch

$(CMDS):	$(APPS)


$(APPS):	FORCE
	make -C $@ $(MAKECMDGOALS)

.PHONY:	FORCE
