#This must be a filename in /usr/share/zoneinfo/.
#Hell.  T2 tiles come from the mountains.  Deal with it.
#WAS: TILE_TIMEZONE:=UTC
TILE_TIMEZONE:=America/Denver

###
FLAG_FILE:=.flagfile_TIMEZONE_CONFIG_COMPLETE
TIMEZONE_FILE:=/usr/share/zoneinfo/$(TILE_TIMEZONE)

all:	FORCE
	@echo "Only 'make install' does anything in $(PWD)"

install:	configure-timezone

configure-timezone:	FORCE
	@if [ -f $(FLAG_FILE) ] ; then \
	  echo "NOTE: '$(FLAG_FILE)' detected; installation skipped" ; \
	else \
	if [ -f $(TIMEZONE_FILE) ] ; then \
	  echo "Configuring for timezone: $(TILE_TIMEZONE)" ; \
	  ln -fs /usr/share/zoneinfo/Navajo /etc/localtime ; \
	  rm -f /etc/timezone ; \
	  dpkg-reconfigure --frontend noninteractive tzdata ; \
	  touch $(FLAG_FILE) ; \
	else \
	  echo "ERROR: Timezone file '$(TIMEZONE_FILE)' not found" && exit 3 ; \
	fi \
	fi \

.PHONY:	FORCE
