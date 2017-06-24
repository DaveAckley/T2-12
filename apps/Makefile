APPS:=$(shell find . -type d -a ! -name ".*" -a ! -path "*/*/*")

CMDS:=build install clean realclean

$(CMDS):	$(APPS)


$(APPS):	FORCE
	make -C $@ $(MAKECMDGOALS)

.PHONY:	FORCE
