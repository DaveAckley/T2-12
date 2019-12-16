#DON'T NEED OUR OWN RPMSG_LIB ANYMORE?
#WAS:PRUDIRS:=lib itcio
PRUDIRS:=itcio

CMDS:=build install clean realclean touch

$(CMDS):	$(PRUDIRS)


$(PRUDIRS):	FORCE
	cd $@; make $(MAKECMDGOALS)

.PHONY:	FORCE
