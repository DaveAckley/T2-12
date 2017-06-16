SUBDIRS:=firmware

all:	$(SUBDIRS)

clean:	$(SUBDIRS)

realclean:	clean $(SUBDIRS)

install:	$(SUBDIRS)

$(SUBDIRS):	FORCE
	$(MAKE) -C $@ $(MAKECMDGOALS)

.PHONY:	all clean realclean install FORCE

