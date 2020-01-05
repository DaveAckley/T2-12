SHELL:=/bin/bash
HOME_DIR:=/home/t2
GITHUB_BASE_DIR:=$(HOME_DIR)/GITHUB

GITHUB_DIRS:=tslib-master
GITHUB_TARGETS:=$(patsubst %,$(GITHUB_BASE_DIR)/%,$(GITHUB_DIRS))

install:	default-pointercal .FLAG_INSTALLED_SDL
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
.FLAG_INSTALLED_SDL:	REMOVE_BASE_PACKAGES
	rm -rf $(TMPSDLDIR)
	mkdir -p $(TMPSDLDIR)
	cp $(SDLZIP) $(TMPSDLDIR)
	pushd $(TMPSDLDIR) && unzip $(SDLZIP) && \
	cd $(TMPSDLDIR)/SDL1.2-master && ./autogen.sh && \
	./configure $(SDLCONFIGUREFLAGS) && \
	make && \
	make install && \
	popd && \
	touch .FLAG_INSTALLED_SDL && \
	echo SDL INSTALLED SUCCESSFULLY

SDLBASEPACKAGES:=libsdl1.2-dev libsdl1.2debian
REMOVE_BASE_PACKAGES:	FORCE
	dpkg -r --force-depends $(SDLBASEPACKAGES) || echo "COULDN'T REMOVE $(SDLBASEPACKAGES)"

.PHONY:	FORCE
