CONF_INPUTS:=pruss-blacklist.conf fbtft.conf
CONF_OUTPUT_DIR:=/etc/modprobe.d
CONF_OUTPUTS:=$(patsubst %,$(CONF_OUTPUT_DIR)/%,$(CONF_INPUTS))

ETC_INPUTS:=rc.local rsyslog.conf
ETC_DIR:=/etc
ETC_OUTPUTS:=$(patsubst %,$(ETC_DIR)/%,$(ETC_INPUTS))


all:
	@echo $(CONF_INPUTS) - $(CONF_OUTPUTS) // $(ETC_INPUTS) - $(ETC_OUTPUTS)

touch:
	touch  $(CONF_INPUTS) $(ETC_INPUTS)

clean:
	@rm -f *~

realclean:	clean touch

install:	$(CONF_OUTPUTS) $(ETC_OUTPUTS)

$(CONF_OUTPUTS):	$(CONF_INPUTS)
	cp $^ $(CONF_OUTPUT_DIR)  || (echo Must be root ; exit 2)

$(ETC_OUTPUTS):	$(ETC_INPUTS)
	cp $^ $(ETC_DIR)  || (echo Must be root ; exit 2)
