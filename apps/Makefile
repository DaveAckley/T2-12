APPS:=$(shell find . -type d -a ! -name ".*")

CMDS:=build install clean

$(CMDS):	$(APPS)


$(APPS):	FORCE
	make -C $@ $(MAKECMDGOALS)

.PHONY:	FORCE
