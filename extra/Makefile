
HOME_DIR:=/home/t2
GITHUB_BASE_DIR:=$(HOME_DIR)/GITHUB

GITHUB_DIRS:=PerlIO-Layers-0.011 File-Map-0.66 GFB MFM 
GITHUB_TARGETS:=$(patsubst %,$(GITHUB_BASE_DIR)/%,$(GITHUB_DIRS))

install:	MAKE_DIRS $(GITHUB_TARGETS) MFMTMP

MAKE_DIRS:	FORCE
	mkdir -p $(HOME_DIR)/GITHUB
	mkdir -p $(HOME_DIR)/MFMTMP

$(GITHUB_BASE_DIR)/PerlIO-Layers-0.011:	PerlIO-Layers-0.011-201902110239.tgz
	tar xvzf $^ -C $(GITHUB_BASE_DIR)
	cd $@;perl Build.PL;./Build install

$(GITHUB_BASE_DIR)/File-Map-0.66:	File-Map-0.66-201902110239.tgz
	tar xvzf $^ -C $(GITHUB_BASE_DIR)
	cd $@;perl Build.PL;./Build install

$(GITHUB_BASE_DIR)/GFB:	GFB-201905202136.tgz
	tar xvzf $^ -C $(GITHUB_BASE_DIR)
	cd $@/Graphics-Framebuffer-6.18;perl Makefile.PL;make install

$(GITHUB_BASE_DIR)/MFM:	MFM20190211SIG.tgz
	tar xvzf $^ -C $(GITHUB_BASE_DIR)

$(GITHUB_BASE_DIR)/ULAM:	ULAM-20190520.tgz
	tar xvzf $^ -C $(GITHUB_BASE_DIR)


MFMTMP:	MFMTMP-20190520.tgz
	tar xvzf $^ -C $(HOME_DIR)

.PHONY:	FORCE
