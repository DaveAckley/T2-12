INPUT:=uEnv.txt
OUTPUT:=/boot/uEnv.txt

all:	FORCE
	@ls -l $(INPUT)

touch:	FORCE
	touch $(INPUT)

clean:	FORCE
	@rm -f *~

realclean:	clean touch

install:	$(OUTPUT)

$(OUTPUT):	$(INPUT)
	cp $< $@  || (echo Must be root ; exit 2)

.PHONY:	FORCE
