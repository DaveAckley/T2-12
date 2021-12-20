SERVICES_STOP+=apache2.service
#AHAX 201912160341 We've now uninstalled bonescript, cloud9, and roboticscape I believe
#SERVICES_STOP+=bonescript-autorun.service bonescript.service bonescript.socket
#SERVICES_STOP+=cloud9.service cloud9.socket
#SERVICES_STOP+=roboticscape.service

FLAG_FILE:=.flagfile_INSTALL_COMPLETE

build:	FORCE
	@echo "SERVICES_STOP: $(SERVICES_STOP)"


install:	build
	@if [ -f $(FLAG_FILE) ] ; then \
	  echo "NOTE: '$(FLAG_FILE)' detected; installation skipped" ; \
	else \
	  for i in $(SERVICES_STOP) ; do \
	    echo "Stopping $$i" ; \
	    systemctl stop $$i || true ; \
	    echo "Disabling $$i" ; \
	    systemctl disable $$i || true ; \
	  done ; \
	  touch $(FLAG_FILE) ; \
	fi

clean:	FORCE
	rm -f *~

realclean:	clean
	rm -f $(FLAG_FILE)


.PHONY:	FORCE
