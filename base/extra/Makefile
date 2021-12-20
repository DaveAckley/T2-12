SHELL:=/bin/bash
HOME_DIR:=/home/t2
GITHUB_BASE_DIR:=$(HOME_DIR)/GITHUB

GITHUB_DIRS:=tslib-master
GITHUB_TARGETS:=$(patsubst %,$(GITHUB_BASE_DIR)/%,$(GITHUB_DIRS))

install:	default-pointercal INSTALL
	@echo BUILDING SDL AND INSTALLING default-pointercal
	cp default-pointercal /etc/pointercal

OLDinstall:	MAKE_DIRS $(GITHUB_TARGETS) 

MAKE_DIRS:	FORCE
	mkdir -p $(GITHUB_BASE_DIR)

$(GITHUB_BASE_DIR)/tslib-master:	tslib-1.20-201906240441.tgz default-pointercal
	tar xvzf $< -C $(GITHUB_BASE_DIR)
	cd $@;mkdir ./build;cd ./build;cmake -DCMAKE_INSTALL_PREFIX:PATH=/usr ..;make;make install
	rm -f /etc/sudoers.d/sdl  # Grrrrrr did tslib make install add this?  It breaks sudo!
	cp default-pointercal /etc/pointercal

TMPSDLDIR:=/tmp/SDLINSTALL
SDLZIP:=sdl1.2-master.zip
SDLCONFIGUREFLAGS:=--enable-video-opengl=no --enable-video-x11=no --enable-esd=no --prefix=/usr
INSTALL:	.FLAG_SDL_INSTALLED

#SDL_BASE_PACKAGES+=libsdl1.2-dev libsdl1.2debian
SDL_EXTRA_PACKAGES+=libsdl-image1.2-dev libsdl-ttf2.0-dev
SDL_BASE_DEBS:=$(wildcard *.deb)

.FLAG_SDL_INSTALLED:	.FLAG_SDL_EXTRA_INSTALLED
	touch $@

.FLAG_SDL_EXTRA_INSTALLED:	.FLAG_SDL_DUMMY_INSTALLED
	apt install -y $(SDL_EXTRA_PACKAGES) && touch $@

.FLAG_SDL_DUMMY_INSTALLED:	.FLAG_SDL_BASE_INSTALLED
	dpkg -i $(SDL_BASE_DEBS) && touch $@

.FLAG_SDL_BASE_INSTALLED:	
	rm -rf $(TMPSDLDIR)
	mkdir -p $(TMPSDLDIR)
	cp $(SDLZIP) $(TMPSDLDIR)
	pushd $(TMPSDLDIR) && unzip $(SDLZIP) && \
	cd $(TMPSDLDIR)/SDL1.2-master && ./autogen.sh && \
	./configure $(SDLCONFIGUREFLAGS) && \
	make && \
	make install && \
	popd && \
	touch $@ && \
	echo SDL INSTALLED SUCCESSFULLY

CLEAN_ALL_FLAGS:	FORCE
	rm -f .FLAG*

.PHONY:	FORCE
