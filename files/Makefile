SUBDIRS:=firmware boot etc opt

all:	$(SUBDIRS)

touch:	$(SUBDIRS)

clean:	$(SUBDIRS)

realclean:	clean $(SUBDIRS)

install:	$(SUBDIRS)

$(SUBDIRS):	FORCE
	$(MAKE) -C $@ $(MAKECMDGOALS)

.PHONY:	all touch clean realclean install FORCE

