CONF_INPUTS:=pruss-blacklist.conf fbtft.conf T2-12-modprobe.conf
CONF_OUTPUT_DIR:=/etc/modprobe.d
CONF_OUTPUTS:=$(patsubst %,$(CONF_OUTPUT_DIR)/%,$(CONF_INPUTS))

ETC_INPUTS:=rsyslog.conf pointercal.xinput
ETC_DIR:=/etc
ETC_OUTPUTS:=$(patsubst %,$(ETC_DIR)/%,$(ETC_INPUTS))

ETC_FSTAB:=/etc/fstab
T2_TMPFS:=/mnt/T2TMP
T2_TMPFS_MNT_CMD:=none $(T2_TMPFS) tmpfs size=1M,mode=1777 0 0

SYSCTL_INPUTS:=T2-12-sysctl.conf
SYSCTL_DIR:=/etc/sysctl.d
SYSCTL_OUTPUTS:=$(patsubst %,$(SYSCTL_DIR)/%,$(SYSCTL_INPUTS))

PROFILE_INPUTS:=sdl.sh
PROFILE_DIR:=/etc/profile.d
PROFILE_OUTPUTS:=$(patsubst %,$(PROFILE_DIR)/%,$(PROFILE_INPUTS))

EMACS_INPUTS:=50acklemacs.el
EMACS_DIR:=/etc/emacs/site-start.d
EMACS_OUTPUTS:=$(patsubst %,$(EMACS_DIR)/%,$(EMACS_INPUTS))

ALL_INPUTS:=$(CONF_INPUTS) $(ETC_INPUTS) $(SYSCTL_INPUTS) $(PROFILE_INPUTS) $(EMACS_INPUTS) $(ETC_FSTAB)

## THIS IS JUST SOMEHOW BROKEN SO DON'T DO IT
#SUDOER_INPUTS:=sdl
#SUDOER_DIR:=/etc/sudoers.d
#SUDOER_OUTPUTS:=$(SUDOER_DIR)/sdl

all:	$(ETC_FSTAB)
	@echo $(ETC_FSTAB)
	@echo $(CONF_INPUTS) - $(CONF_OUTPUTS)
	@echo $(ETC_INPUTS) - $(ETC_OUTPUTS)
	@echo $(SYSCTL_INPUTS) - $(SYSCTL_OUTPUTS)
	@echo $(PROFILE_INPUTS) - $(PROFILE_OUTPUTS) 
	@echo $(EMACS_INPUTS) - $(EMACS_OUTPUTS) 

touch:	FORCE
	touch $(ALL_INPUTS)

clean:
	@rm -f *~

realclean:	clean touch

install:	touch $(CONF_OUTPUTS) $(ETC_OUTPUTS) $(SYSCTL_OUTPUTS) $(PROFILE_OUTPUTS) $(EMACS_OUTPUTS) $(ETC_FSTAB)

$(CONF_OUTPUTS):	$(CONF_INPUTS)
	cp $^ $(CONF_OUTPUT_DIR)  || (echo Must be root ; exit 2)

$(ETC_FSTAB):	FORCE
	@grep ' $(T2_TMPFS) ' $(ETC_FSTAB) || ( \
		echo $(T2_TMPFS_MNT_CMD) >>$(ETC_FSTAB) && \
		echo ADDED $(T2_TMPFS) TO $(ETC_FSTAB) && \
		mkdir -p $(T2_TMPFS) && \
		mount -a && \
		df $(T2_TMPFS) && \
		echo MOUNTED $(T2_TMPFS) TO $(ETC_FSTAB) )

$(ETC_OUTPUTS):	$(ETC_INPUTS)
	cp $^ $(ETC_DIR)  || (echo Must be root ; exit 2)

$(SYSCTL_OUTPUTS):	$(SYSCTL_INPUTS)
	cp $^ $(SYSCTL_DIR)  || (echo Must be root ; exit 2)

$(PROFILE_OUTPUTS):	$(PROFILE_INPUTS)
	mkdir -p $(PROFILE_DIR)
	cp -a $^ $(PROFILE_DIR)  || (echo Must be root ; exit 2)

$(EMACS_OUTPUTS):	$(EMACS_INPUTS)
	mkdir -p $(EMACS_DIR)
	cp -a $^ $(EMACS_DIR)  || (echo Must be root ; exit 2)

#$(SUDOER_OUTPUTS):	$(SUDOER_INPUTS)
#	mkdir -p $(SUDOER_DIR)
#	cp $^ $(SUDOER_DIR)  || (echo Must be root ; exit 2)

.PHONY:	FORCE
