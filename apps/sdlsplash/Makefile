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

install: 
	@echo '(install target not yet implemented)'

clean:	
	rm -f *~

realclean:	clean

.PHONY:	FORCE


