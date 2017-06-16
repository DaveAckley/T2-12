INPUT:=uEnv.txt
OUTPUT:=/boot/uEnv.txt

all:
	@ls -l $(INPUT)

clean:
	@rm -f *~

realclean:	clean

install:	$(OUTPUT)

$(OUTPUT):	$(INPUT)
	cp $< $@  || (echo Must be root ; exit 2)
