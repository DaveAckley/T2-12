GITHUB_DIRS:=PerlIO-Layers-0.011 File-Map-0.66 GFB MFM 
GITHUB_TARGETS:=$(patsubst %,GITHUB/%,$(GITHUB_DIRS))

install:	MAKE_DIRS $(GITHUB_TARGETS) MFMTMP

MAKE_DIRS:	FORCE
	mkdir -p GITHUB
	mkdir -p MFMTMP

GITHUB/PerlIO-Layers-0.011:	PerlIO-Layers-0.011-201902110239.tgz
	tar xvzf $^ -C GITHUB
	cd $@;perl Build.PL;./Build install

GITHUB/File-Map-0.66:	File-Map-0.66-201902110239.tgz
	tar xvzf $^ -C GITHUB
	cd $@;perl Build.PL;./Build install

GITHUB/GFB:	GFB-201902110239.tgz
	tar xvzf $^ -C GITHUB
	cd $@/Graphics-Framebuffer-6.18;perl Makefile.PL;make install

GITHUB/MFM:	MFM20190211SIG.tgz
	tar xvzf $^ -C GITHUB

GITHUB/ULAM:	ULAM-20190520.tgz
	tar xvzf $^ -C GITHUB


MFMTMP:	MFMTMP-20190520.tgz
	tar xvzf $^ .

.PHONY:	FORCE
