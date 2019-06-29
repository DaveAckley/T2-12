
HOME_DIR:=/home/t2
GITHUB_BASE_DIR:=$(HOME_DIR)/GITHUB

GITHUB_DIRS:=tslib-master
GITHUB_TARGETS:=$(patsubst %,$(GITHUB_BASE_DIR)/%,$(GITHUB_DIRS))

install:	MAKE_DIRS $(GITHUB_TARGETS) 

MAKE_DIRS:	FORCE
	mkdir -p $(HOME_DIR)/GITHUB

$(GITHUB_BASE_DIR)/tslib-master:	tslib-1.20-201906240441.tgz default-pointercal
	tar xvzf $^ -C $(GITHUB_BASE_DIR)
	cd $@;mkdir ./build;cd ./build;cmake ..;make;make install
	cp default-pointercal /etc/pointercal

.PHONY:	FORCE
