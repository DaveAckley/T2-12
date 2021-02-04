lockstats:	lockstats.c ../../*.h
	gcc -Wall -Wstrict-prototypes -Werror -g2 -I../../ $< -o $@

ARGS:=speed1
run:	lockstats 
	./$^ $(ARGS)
