#DON'T NEED OUR OWN RPMSG_LIB ANYMORE?
#WAS:PRUDIRS:=lib itcio
PRUDIRS:=lib itcio

CMDS:=build install clean realclean touch

$(CMDS):	$(PRUDIRS)


$(PRUDIRS):	check_bin
	cd $@; make $(MAKECMDGOALS)


check_bin:	FORCE
	@if [ ! -L /usr/share/ti/cgt-pru/bin ] ; then \
	  ln -s /usr/bin /usr/share/ti/cgt-pru/bin ;\
	  echo Linked /usr/bin to /usr/share/ti/cgt-pru/bin ;\
	fi ;\


.PHONY:	FORCE
