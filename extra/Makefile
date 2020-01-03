
HOME_DIR:=/home/t2
GITHUB_BASE_DIR:=$(HOME_DIR)/GITHUB

GITHUB_DIRS:=tslib-master
GITHUB_TARGETS:=$(patsubst %,$(GITHUB_BASE_DIR)/%,$(GITHUB_DIRS))

install:	default-pointercal
	@echo BUILDING NOTHING EXTRA AND JUST INSTALLING default-pointercal
	cp default-pointercal /etc/pointercal

OLDinstall:	MAKE_DIRS $(GITHUB_TARGETS) 

MAKE_DIRS:	FORCE
	mkdir -p $(GITHUB_BASE_DIR)

$(GITHUB_BASE_DIR)/tslib-master:	tslib-1.20-201906240441.tgz default-pointercal
	tar xvzf $< -C $(GITHUB_BASE_DIR)
	cd $@;mkdir ./build;cd ./build;cmake -DCMAKE_INSTALL_PREFIX:PATH=/usr ..;make;make install
	rm -f /etc/sudoers.d/sdl  # Grrrrrr did tslib make install add this?  It breaks sudo!
	cp default-pointercal /etc/pointercal

.PHONY:	FORCE
