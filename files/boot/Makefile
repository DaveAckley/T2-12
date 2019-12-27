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

$(OUTPUT):	$(INPUT)
	cat $< | sed 's/^uname_r=\(.*\)$/uname_r='`uname -r`'/' > $@  || (echo Must be root ; exit 2)

.PHONY:	FORCE
