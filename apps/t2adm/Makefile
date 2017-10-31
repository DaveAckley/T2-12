APP_NAME:=t2adm
SRCS:=$(wildcard *.cpp)
OBJS:=$(patsubst %.cpp,%.o,$(SRCS))
HDRS:=$(patsubst %.cpp,%.h,$(SRCS))

CFLAGS += -Wall -Werror -pedantic -ansi -g2 -fno-stack-protector
LIBS += -lncurses

CMDS:=build touch install clean realclean
$(CMDS):	FORCE

run:	build
	xterm -e ./$(APP_NAME) 

build:	$(APP_NAME)

$(APP_NAME):	$(OBJS)
	g++ $^ -o $@  $(LIBS) 

%.o:	%.cpp $(HDRS) Makefile
	g++ $(CFLAGS) $< -c

t2adc.h:	ntc.pl Makefile
	./ntc.pl header > $@

t2adc.cpp:	ntc.pl Makefile
	./ntc.pl table > $@

touch:	FORCE
	touch $(SRCS)

install: $(APP_NAME)
	mkdir -p /opt/scripts/t2
	cp $< /opt/scripts/t2/ || (echo must be root ; exit 2)

clean:	
	rm -f *~

realclean:	clean

.PHONY:	FORCE


