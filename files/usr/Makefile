USR_XORG_INPUTS:=99-calibration.conf
USR_XORG_DIR:=/usr/share/X11/xorg.conf.d/
USR_XORG_OUTPUTS:=$(patsubst %,$(USR_XORG_DIR)/%,$(USR_XORG_INPUTS))

all:
	@echo $(USR_XORG_INPUTS) - $(USR_XORG_DIR)

touch:
	touch  $(USR_XORG_INPUTS)

clean:
	@rm -f *~

realclean:	clean touch

install:	$(USR_XORG_OUTPUTS)

$(USR_XORG_OUTPUTS):	$(USR_XORG_INPUTS)
	if test -d $(USR_XORG_DIR) ; then \
	cp $^ $(USR_XORG_DIR)  || (echo Must be root ; exit 2) \
	fi

