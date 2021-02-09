#!/usr/bin/perl -w

use File::Spec;
use File::Path qw(make_path);

use POSIX; # For strftime

my ($slot,$lang,$undef) = @ARGV;
die "Usage: $0 SLOT LANG\n"
    unless defined $slot and defined $lang;
$lang = lc($lang);
die "Usage: $0 HEXSLOT SPLAT|ulam\n"
    unless $slot =~ /^[[:xdigit:]]{2}$/ and $lang =~ /^splat|ulam$/;
my $slotnum = hex($slot);
die "Usage: $0 a0..ef\n" unless $slotnum >= 0xa0 && $slotnum <= 0xef;

my $destpath = File::Spec->rel2abs("./$slot");
die "'$destpath' already exists\n" if -e $destpath;
my @subdirs = qw(code notes);
for my $sub (@subdirs) {
    my $subpath = "$destpath/$sub";
    die "Can't make directory '$subpath'\n" unless make_path($subpath);
}

genTopMakefile($destpath);
genSPLATCodeFiles("$destpath/code") if $lang eq "splat";
genUlamCodeFiles("$destpath/code") if $lang eq "ulam";

print "DONE\n";
exit;

###########################
sub genTopMakefile {
    my $dir = shift;
    my $file = "$dir/Makefile";
    die if -e $file;
    open FH, ">", $file or die "Can't write $file: $!";
    print FH <<'EOF';
##STANDARD TOP-LEVEL MAKEFILE FOR PHYSICS SLOTS
SHELL:=/bin/bash

all:	t2

TAR_SWITCHES+=--exclude=*~ --exclude=.git --exclude-backups
TAR_SWITCHES+=--exclude=.gen
TAR_SWITCHES+=--exclude=*.mfz

TAR_SWITCHES+=--mtime="2008-01-02 12:34:56"
TAR_SWITCHES+=--owner=0 --group=0 --numeric-owner 

REGNUM:=0
SLOTNUM:=$(lastword $(subst /, ,$(dir $(realpath $(firstword $(MAKEFILE_LIST))))))
DESTDIR:=$(abspath ..)
TAG_PATH:=$(DESTDIR)/slot$(SLOTNUM)-install-tag.dat

TAR_FILE:=$(SLOTNUM)-built.tgz
TAR_FILE_DIR:=$(abspath ..)
TAR_PATH:=$(TAR_FILE_DIR)/$(TAR_FILE)

$(TAR_PATH):	FORCE
	pushd ..;tar cvzf $(TAR_PATH) $(TAR_SWITCHES) $(SLOTNUM);popd

cdmd:	t2 $(TAR_PATH)
	@pushd .. ; \
	FN=`/home/t2/MFM/bin/mfzmake cdmake $(REGNUM) $(SLOTNUM) Physics-$(SLOTNUM) $(TAR_PATH) | \
            perl -e "while(<>) {/'([^']+)'/ && print "'$$1}'`; \
	if [ "x$$FN" = "x" ] ; then echo "Build failed" ; else  \
	echo -n "Got $$FN for $(SLOTNUM), tag = "; \
	perl -e '"'$$FN'" =~ /[^-]+-[^-]+-([[:xdigit:]]+)[.]/; print $$1' > $(TAG_PATH); \
	cat $(TAG_PATH); \
	echo -n ", size = " ; stat -c %s $$FN; \
	echo "TO RELEASE:" ; \
	echo "  cp $(TAG_PATH) /cdm/tags ; cp $(DESTDIR)/$$FN /cdm/common"; \
	fi; \
	popd

install:	FORCE
	@echo "Make install not yet implemented for physics"
	@echo "We don't know what it should do"
	@echo "So doing nothing seems like a success for now"


code:	FORCE
	make -C code

clean:	FORCE
	make -C code clean
	rm -f *~

realclean:	FORCE
	make -C code realclean
	rm -f *.so

SUBDIR_CMDS:=run ishtar t2

$(SUBDIR_CMDS):	FORCE
	make -C code $@

.PHONY:	FORCE $(SUBDIR_CMDS)
EOF

    close FH or die "Can't close '$file': $!";
    print "[Created $file]\n";
}

sub genUlamCodeFiles {
    my $dir = shift;
    genCodeMakefile($dir);
    genDemoElementUlam($dir);
    genSeedUlam($dir);
}

sub genSPLATCodeFiles {
    my $dir = shift;
    genCodeMakefile($dir);
    genDemoElementSPLAT($dir);
    genSeedSPLAT($dir);
}

sub genCodeSPLATFile {
    my $dir = shift;
    my $file = "$dir/Makefile";
    die if -e $file;
    open FH, ">", $file or die "Can't write $file: $!";
    print FH <<'EOF';
##STANDARD TOP-LEVEL MAKEFILE FOR PHYSICS SLOTS
SHELL:=/bin/bash

all:	t2

TAR_SWITCHES+=--exclude=*~ --exclude=.git --exclude-backups
TAR_SWITCHES+=--exclude=.gen
TAR_SWITCHES+=--exclude=*.mfz

TAR_SWITCHES+=--mtime="2008-01-02 12:34:56"
TAR_SWITCHES+=--owner=0 --group=0 --numeric-owner 

REGNUM:=0
SLOTNUM:=$(lastword $(subst /, ,$(dir $(realpath $(firstword $(MAKEFILE_LIST))))))
DESTDIR:=$(abspath ..)
TAG_PATH:=$(DESTDIR)/slot$(SLOTNUM)-install-tag.dat

TAR_FILE:=$(SLOTNUM)-built.tgz
TAR_FILE_DIR:=$(abspath ..)
TAR_PATH:=$(TAR_FILE_DIR)/$(TAR_FILE)

$(TAR_PATH):	FORCE
	pushd ..;tar cvzf $(TAR_PATH) $(TAR_SWITCHES) $(SLOTNUM);popd

cdmd:	t2 $(TAR_PATH)
	@pushd .. ; \
	FN=`/home/t2/MFM/bin/mfzmake cdmake $(REGNUM) $(SLOTNUM) Physics-$(SLOTNUM) $(TAR_PATH) | \
            perl -e "while(<>) {/'([^']+)'/ && print "'$$1}'`; \
	if [ "x$$FN" = "x" ] ; then echo "Build failed" ; else  \
	echo -n "Got $$FN for $(SLOTNUM), tag = "; \
	perl -e '"'$$FN'" =~ /[^-]+-[^-]+-([[:xdigit:]]+)[.]/; print $$1' > $(TAG_PATH); \
	cat $(TAG_PATH); \
	echo -n ", size = " ; stat -c %s $$FN; \
	echo "TO RELEASE:" ; \
	echo "  cp $(TAG_PATH) /cdm/tags ; cp $(DESTDIR)/$$FN /cdm/common"; \
	fi; \
	popd

install:	FORCE
	@echo "Make install not yet implemented for physics"
	@echo "We don't know what it should do"
	@echo "So doing nothing seems like a success for now"


code:	FORCE
	make -C code

clean:	FORCE
	make -C code clean
	rm -f *~

realclean:	FORCE
	make -C code realclean
	rm -f *.so

SUBDIR_CMDS:=run ishtar t2

$(SUBDIR_CMDS):	FORCE
	make -C code $@

.PHONY:	FORCE $(SUBDIR_CMDS)
EOF

    close FH or die "Can't close '$file': $!";
    print "[Created $file]\n";
}

sub genCodeMakefile {
    my $dir = shift;
    my $file = "$dir/Makefile";
    die if -e $file;
    open FH, ">", $file or die "Can't write $file: $!";
    print FH <<'EOF';
# Customize ULAM_BIN_DIR, MFM_BIN_DIR, and SPLAT_BIN_DIR if necessary
ULAM_BIN_DIR:=/home/t2/ULAM/bin
MFM_BIN_DIR:=/home/t2/MFM/bin
SPLAT_BIN_DIR:=/home/t2/SPLATTR/bin

NAME:=$(notdir $(realpath ..))
THIS_DIR:=$(strip $(notdir $(shell dirname $(realpath $(lastword $(MAKEFILE_LIST))))))
MFZ:=../$(NAME).mfz
ULAM:=$(ULAM_BIN_DIR)/ulam
MFZRUN:=$(MFM_BIN_DIR)/mfzrun
SPLATTR:=$(SPLAT_BIN_DIR)/splattr.sh
#UFLAGS:=-g --sa
#UFLAGS:=--sa
UFLAGS:=-o
ARGS_TXT_FILES:=$(wildcard args.txt)
SPLAT_FILES:=$(wildcard *.splat)
ULAM_FILES:=$(wildcard *.ulam)
INC_FILES:=$(wildcard *.inc)
TIMESTAMP:=$(shell date +%Y%m%d-%H%M%S)
DEV:=$(shell whoami)
ISHNAME:=$(TIMESTAMP)-$(DEV)
T2TARGET:=$(abspath ../libcue.so)

all:	$(MFZ)

t2:	$(T2TARGET)

$(T2TARGET):	$(MFZ)
	cp .gen/bin/libcue.so $@

run:	$(MFZ)
	$(MFZRUN) $(MFZ)

ifeq ($(SPLAT_FILES),)
$(MFZ):	$(ULAM_FILES) $(ARGS_TXT_FILES) | Makefile
	$(ULAM) $(UFLAGS) $^ $@
else
$(MFZ):	$(SPLAT_FILES) $(ULAM_FILES) $(ARGS_TXT_FILES) | Makefile
	$(SPLATTR) $(UFLAGS) $^ $@
endif

clean:	
	rm -f *~

realclean: clean
	rm -f $(MFZ)
	rm -rf .gen

ishtar:
	@make realclean
	@make >ISH-BUILD-STDOUT.txt 2>ISH-BUILD-STDERR.txt || true
	@cd ..;tar cvzf $(ISHNAME).tgz $(THIS_DIR) --transform s/^$(THIS_DIR)/$(ISHNAME)/
	@echo Made ../$(ISHNAME).tgz

.PHONY:	all mfz clean realclean tar ishtar
EOF

    close FH or die "Can't close '$file': $!";
    print "[Created $file]\n";
}

sub genDemoElementUlam {
    my $dir = shift;
    my $file = "$dir/MyElement.ulam";
    die if -e $file;
    open FH, ">", $file or die "Can't write $file: $!";
    print FH <<'EOF';
/** An element of mine.  To be hacked/copied/renamed/etc.
  \symbol ME
  \color #f00
 */
element MyElement {
  Void behave() {
    Fail f;      
    f.fail();     // Replace with whatever success means to me!
  }
}

EOF
    close FH or die "Can't close '$file': $!";
    print "[Created $file]\n";
}

sub genSeedUlam {
    my $dir = shift;
    my $file = "$dir/S.ulam";
    die if -e $file;
    open FH, ">", $file or die "Can't write $file: $!";
    my $year = strftime("%Y", localtime());
    print FH <<"EOF";
/** My T2 Seed.  This is the start symbol. 
    It must be named 'S', with the symbol 'S'.
  \\symbol S
  \\author Myname Here
  \\copyright (C) $year
  \\license lgpl
 */
element S {
  EventWindow ew;
  Void behave() {
    ew[0] = MyElement.instanceof;  // Decay into a MyElement!
  }
}
EOF
    close FH or die "Can't close '$file': $!";
    print "[Created $file]\n";
}

sub genSeedSPLAT {
    my $dir = shift;
    my $file = "$dir/S.splat";
    die if -e $file;
    open FH, ">", $file or die "Can't write $file: $!";
    my $year = strftime("%Y", localtime());
    print FH <<"EOF";
= element S.  Decay into a MyElement
\\color #222
\\symbol S
\\author Myname Here
\\copyright (C) $year
\\license lgpl

== Rules

given M isa MyElement

 @ -> M    

EOF
    close FH or die "Can't close '$file': $!";
    print "[Created $file]\n";
}

sub genDemoElementSPLAT {
    my $dir = shift;
    my $file = "$dir/MyElement.splat";
    die if -e $file;
    open FH, ">", $file or die "Can't write $file: $!";
    print FH <<'EOF';
# (This is just a renaming of SwapLine, described in http://doi.org/cshp)
= element MyElement.  My demo element that does stuff.
\color #222
\symbol ME

==  Rules
given s : true
vote s isa MyElement

 s@ -> _.    # Thin out

 s      .
  @ ->   .   # Catch up
 s      .

 @x -> x@    # Swap on

EOF
    close FH or die "Can't close '$file': $!";
    print "[Created $file]\n";
}
