APP_NAME:=sdlsplash
DEMO_FILE:=../../files/opt/MFM-T2-10.png
SRCS:=$(APP_NAME).cpp
OBJS:=$(patsubst %.cpp,%.o,$(SRCS))

CFLAGS += -Wall -Werror -pedantic -ansi
CFLAGS += $(shell sdl-config --cflags)

LIBS += -lSDL_ttf -lSDL_image -lSDL -lpng -lm

CMDS:=build touch install clean realclean
$(CMDS):	FORCE

run:	build
	./$(APP_NAME) $(DEMO_FILE)

build:	$(APP_NAME)

$(APP_NAME):	$(OBJS)
	g++ $^ -o $@  $(LIBS) 

%.o:	%.cpp Makefile
	g++ $(CFLAGS) $< -c


touch:	FORCE
	touch $(SRCS)

install: $(APP_NAME)
	mkdir -p /opt/scripts/t2
	unlink /opt/scripts/t2/sdlsplash || echo no existing sdlsplash
	cp $< /opt/scripts/t2/ || (echo status=$$?, must be root? ; exit 2)

clean:	
	rm -f *~

realclean:	clean

.PHONY:	FORCE


