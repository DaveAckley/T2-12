MODULES:=itc_pkt

CMDS:=build install clean realclean touch

$(CMDS):	$(MODULES)


$(MODULES):	FORCE
	cd $@; make $(MAKECMDGOALS)

.PHONY:	FORCE
