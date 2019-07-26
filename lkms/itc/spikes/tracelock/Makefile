PROG:=tracelock
CFLAGS:=-g -Wall -Wstrict-prototypes -Werror
CFLAGS+=-I../..
$(PROG):	$(PROG).c ../../*.h Makefile
	gcc $(CFLAGS) $< -o $@

ARGS:=speed1
run:	$(PROG) 
	./$^ $(ARGS)
