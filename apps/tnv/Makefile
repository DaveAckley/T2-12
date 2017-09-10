APP_NAME:=tnv
SRCS:=$(APP_NAME).cpp t2adc.cpp
OBJS:=$(patsubst %.cpp,%.o,$(SRCS))
HDRS:=$(patsubst %.cpp,%.h,$(SRCS))

CFLAGS += -Wall -Werror -pedantic -ansi
LIBS += 

CMDS:=build touch install clean realclean
$(CMDS):	FORCE

run:	build
	./$(APP_NAME) 

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


