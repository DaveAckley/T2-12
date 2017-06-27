INPUT:=pruss-blacklist.conf
OUTPUT:=/etc/modprobe.d/pruss-blacklist.conf
INPUT2:=rc.local
OUTPUT2:=/etc


all:
	@ls -l $(INPUT) $(INPUT2)

touch:
	touch $(INPUT) $(INPUT2)

clean:
	@rm -f *~

realclean:	clean touch

install:	$(OUTPUT) $(OUTPUT2)

$(OUTPUT):	$(INPUT)
	cp $< $@  || (echo Must be root ; exit 2)

$(OUTPUT2):	$(INPUT2)
	cp $< $@  || (echo Must be root ; exit 2)
