CONF_INPUTS:=pruss-blacklist.conf fbtft.conf T2-12-modprobe.conf
CONF_OUTPUT_DIR:=/etc/modprobe.d
CONF_OUTPUTS:=$(patsubst %,$(CONF_OUTPUT_DIR)/%,$(CONF_INPUTS))

ETC_INPUTS:=rsyslog.conf pointercal.xinput
ETC_DIR:=/etc
ETC_OUTPUTS:=$(patsubst %,$(ETC_DIR)/%,$(ETC_INPUTS))

PROFILE_INPUTS:=sdl.sh
PROFILE_DIR:=/etc/profile.d
PROFILE_OUTPUTS:=$(patsubst %,$(PROFILE_DIR)/%,$(PROFILE_INPUTS))

EMACS_INPUTS:=50acklemacs.el
EMACS_DIR:=/etc/emacs/site-start.d
EMACS_OUTPUTS:=$(patsubst %,$(EMACS_DIR)/%,$(EMACS_INPUTS))

## THIS IS JUST SOMEHOW BROKEN SO DON'T DO IT
#SUDOER_INPUTS:=sdl
#SUDOER_DIR:=/etc/sudoers.d
#SUDOER_OUTPUTS:=$(SUDOER_DIR)/sdl

all:
	@echo $(CONF_INPUTS) - $(CONF_OUTPUTS)
	@echo $(ETC_INPUTS) - $(ETC_OUTPUTS)
	@echo $(PROFILE_INPUTS) - $(PROFILE_OUTPUTS) 
	@echo $(EMACS_INPUTS) - $(EMACS_OUTPUTS) 
#	@echo $(SUDOER_INPUTS) - $(SUDOER_OUTPUTS)

touch:
	touch  $(CONF_INPUTS) $(ETC_INPUTS)

clean:
	@rm -f *~

realclean:	clean touch

install:	$(CONF_OUTPUTS) $(ETC_OUTPUTS) $(PROFILE_OUTPUTS) $(EMACS_OUTPUTS) #$(SUDOER_OUTPUTS)

$(CONF_OUTPUTS):	$(CONF_INPUTS)
	cp $^ $(CONF_OUTPUT_DIR)  || (echo Must be root ; exit 2)

$(ETC_OUTPUTS):	$(ETC_INPUTS)
	cp $^ $(ETC_DIR)  || (echo Must be root ; exit 2)

$(PROFILE_OUTPUTS):	$(PROFILE_INPUTS)
	mkdir -p $(PROFILE_DIR)
	cp -a $^ $(PROFILE_DIR)  || (echo Must be root ; exit 2)

$(EMACS_OUTPUTS):	$(EMACS_INPUTS)
	mkdir -p $(EMACS_DIR)
	cp -a $^ $(EMACS_DIR)  || (echo Must be root ; exit 2)

#$(SUDOER_OUTPUTS):	$(SUDOER_INPUTS)
#	mkdir -p $(SUDOER_DIR)
#	cp $^ $(SUDOER_DIR)  || (echo Must be root ; exit 2)
