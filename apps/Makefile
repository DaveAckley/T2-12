APPS:=$(shell find . -type d -a ! -name ".*" -a ! -path "*/*/*")

CMDS:=build install clean

$(CMDS):	$(APPS)


$(APPS):	FORCE
	make -C $@ $(MAKECMDGOALS)

.PHONY:	FORCE
