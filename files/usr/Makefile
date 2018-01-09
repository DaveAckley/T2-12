USR_XORG_INPUTS:=99-calibration.conf
USR_XORG_DIR:=/usr/share/X11/xorg.conf.d/
USR_XORG_OUTPUTS:=$(patsubst %,$(USR_XORG_DIR)/%,$(USR_XORG_INPUTS))
ALL_OUTPUTS+=$(USR_XORG_OUTPUTS)

USR_SBIN_INPUTS:=ppru cpru
USR_SBIN_DIR:=/usr/local/sbin
USR_SBIN_OUTPUTS:=$(patsubst %,$(USR_SBIN_DIR)/%,$(USR_SBIN_INPUTS))
ALL_OUTPUTS+=$(USR_SBIN_OUTPUTS)

all:
	@echo $(USR_XORG_INPUTS) - $(USR_XORG_DIR)
	@echo $(USR_SBIN_INPUTS) - $(USR_SBIN_DIR)

touch:
	touch  $(USR_XORG_INPUTS)

clean:
	@rm -f *~

realclean:	clean touch

install:	$(ALL_OUTPUTS)

$(USR_XORG_OUTPUTS):	$(USR_XORG_INPUTS)
	if test -d $(USR_XORG_DIR) ; then \
	cp $^ $(USR_XORG_DIR)  || (echo Must be root ; exit 2) \
	fi

$(USR_SBIN_OUTPUTS):	$(USR_SBIN_INPUTS)
	if test -d $(USR_SBIN_DIR) ; then \
	cp -a $^ $(USR_SBIN_DIR)  || (echo Must be root ; exit 2) \
	fi

