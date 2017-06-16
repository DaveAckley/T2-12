DTS_FILES:=$(wildcard *dts)
DTB_FILES:=$(patsubst %.dts,%.dtb,$(DTS_FILES))

all:	$(DTB_FILES) 
	@echo $(DTS_FILES) / $(DTB_FILES)

%.dtb:	%.dts
	dtc $^


clean:	FORCE
	rm *~

realclean:	clean
	rm *.dtb

install:	$(SUBDIRS)

$(SUBDIRS):	FORCE
	$(MAKE) -C $@ $(MAKECMDGOALS)

.PHONY:	all clean realclean install FORCE

