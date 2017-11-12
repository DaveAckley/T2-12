PRUDIRS:=module firmware

CMDS:=build install clean realclean touch

$(CMDS):	$(PRUDIRS)


$(PRUDIRS):	FORCE
	cd $@; make PRU_CGT=/usr/share/ti/cgt-pru $(MAKECMDGOALS)

.PHONY:	FORCE
