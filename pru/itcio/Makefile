PRUDIRS:=firmware module

CMDS:=build install clean realclean touch

$(CMDS):	$(PRUDIRS)


$(PRUDIRS):	FORCE
	cd $@; make $(MAKECMDGOALS)

.PHONY:	FORCE
