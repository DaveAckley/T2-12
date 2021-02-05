INPUT:=uEnv.txt
OUTPUT:=/boot/uEnv.txt

all:	FORCE
	@ls -l $(INPUT)

touch:	FORCE
	touch $(INPUT)

clean:	FORCE
	@rm -f *~

realclean:	clean touch

install:	touch $(OUTPUT)

DOLLAR:=$
UNAME_R:=$(shell uname -r)
CMD:=s/^uname_r=\(.*\)$(DOLLAR)/uname_r=$(UNAME_R)/

$(OUTPUT):	$(INPUT)
	cat $< | sed "$(CMD)" > $@ || (echo Must be root ; exit 2)

.PHONY:	FORCE
