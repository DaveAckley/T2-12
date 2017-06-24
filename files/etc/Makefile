INPUT:=pruss-blacklist.conf
OUTPUT:=/etc/modprobe.d/pruss-blacklist.conf

all:
	@ls -l $(INPUT)

clean:
	@rm -f *~

realclean:	clean
	touch $(INPUT)   # Don't want to remove $(OUTPUT), so fake-update $(INPUT)

install:	$(OUTPUT)

$(OUTPUT):	$(INPUT)
	cp $< $@  || (echo Must be root ; exit 2)
