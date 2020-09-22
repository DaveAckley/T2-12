package ActionState;
use fields qw(
    mStep
    mSlotNum
    mCurDir
    mTarDirName
    mTarDirPath
    mInstallationDir
    mCDMDir
    mSlotName
    mLastOp
    mModel
    mSC
    mTagDir
    );

use DP qw(:all);
use T2Utils qw(:fileops :processops);
use Constants qw(:all);
use MFZUtils qw(:functions);
use File::Temp qw(tempdir);
use File::Path qw(make_path remove_tree);

BEGIN {
    sub actionRoutines {
        my %h;
        for my $sc (@Constants::SC_CONSTANTS) {
            my $fnc = "do$sc";
            $h{$sc} = \&$fnc;
        }
        return \%h;
    }
}

use constant ACTION_ROUTINES => actionRoutines();

sub new {
    my SlotConfig $sc = shift || die;
    my MFZModel $model = shift || die;
    
    my $mfzpath = $model->makePath();
    die unless -r $mfzpath;

    my $targetdir = $sc->{mTargetDir} || "/tmp";

    initDir($targetdir) or die "Couldn't mkdir $targetdir: $!";

    my CDM $cdm = $model->{mCDM} || die;
    my $cdmdir = $cdm->getBaseDirectory();

    my $tagdir = $cdmdir."/".SUBDIR_TAGS;
    initDir($tagdir) or die "Couldn't mkdir $tagdir: $!";

    my $self = fields::new(__PACKAGE__);   # ActionState
    $self->{mStep} = [];                               # Stack of step numbers
    $self->{mSlotNum} = SSSlot($model->{mSlotStamp});  # Slot number as number
    $self->{mCDMDir} = $cdmdir;                        # cdm base dir
    $self->{mSlotName} = sprintf("slot%02x",$self->{mSlotNum}); # name for files associated with slot
    $self->{mCurDir} = [$targetdir];                   # Stack of pushed dirs        
    $self->{mTarDirName} = undef;                      # Set by successful doSC_UNTARCD
    $self->{mTarDirPath} = undef;                      # Set by successful doSC_UNTARCD
    $self->{mInstallationDir} = undef;                 # Set by successful doSC_TARTAR
    $self->{mLastOp} = undef;                          # Previous operation if any
    $self->{mModel} = $model;                          # The MFZModel we're working with
    $self->{mSC} = $sc;                                # Our SlotConfig
    $self->{mTagDir} = $tagdir;                        # Base dir for tag info
    return $self;
}

sub doActions {
    my __PACKAGE__ $self = shift || die;
    my $actions = shift || die;
    my $ret = 0;
    push @{$self->{mStep}}, 0;
    for my $action (@{$actions}) {
        my $stepno = ++$self->{mStep}->[-1];
        my $steplabel = join(".",@{$self->{mStep}}).".";
        if (ref($action) eq 'ARRAY') {
            $ret = $self->doActions($action);
        } else {
            my $op = ACTION_ROUTINES->{$action};
            die "No action for $action" unless defined $op;
            DPSTD($self->{mModel}->getTag()." $steplabel $action");
            $ret = $op->($self);  # Hmm call in non-OO style?
            $self->{mLastOp} = $action;
        }
        next unless $ret;
        last if $ret > 0;
        die if $ret < 0;
    }
    pop @{$self->{mStep}};
    return $ret;
}

#return 1 if no action needed by tag
sub getTagPath {
    my __PACKAGE__ $self = shift || die;
    my $model = $self->{mModel} || die;
    my $tagpath = sprintf("%s/%s-install-tag.dat", $self->{mTagDir}, $self->{mSlotName});
    return $tagpath;
}

sub doSC_CHKTAG {
    my __PACKAGE__ $self = shift || die;
    my $model = $self->{mModel} || die;
    my $ss = $model->{mSlotStamp};
    my $stamp = SSStamp($ss);
    my $tagfile = $self->getTagPath();

    DPSTD($model->getTag()." -Checking for $tagfile");

    if (-r $tagfile) {
        open my $fh,'<',$tagfile or die "Can't read $tagfile: $!";
        my $line = <$fh>;
        close $fh or die "close $tagfile: $!";
        $line ||= "";
        chomp $line;
        if ($line !~ /^([0-9a-zA-Z]+)$/) {
            DPSTD($model->getTag()." CHKTAG: Ignoring malformed $tagfile ($line)");
        } else {
            my $currentstamp = hex($1);
            if ($stamp == $currentstamp) {
                DPSTD($model->getTag()." CHKTAG: We are up to date; nothing to do");
                return 1;
            }

            if ($stamp < $currentstamp) {
                DPSTD($model->getTag()." CHKTAG: Candidate appears outdated vs ".sprintf("%06x", $currentstamp));
                DPSTD($model->getTag()." CHKTAG: NOT INSTALLING. Delete $tagfile to allow this install");
                return 1;
            }
        }
    }
    DPSTD($model->getTag()." -Tag update needed: PROCEEDING");
    return 0;
}

sub doSC_SETTAG {
    my __PACKAGE__ $self = shift || die;
    my $model = $self->{mModel} || die;
    my $ss = $model->{mSlotStamp} || die;
    my $stamp = SSStamp($ss);
    my $hexstamp = sprintf("%x",$stamp);
    my $tagfile = $self->getTagPath();
    open my $fh,'>',$tagfile or die "Can't write $tagfile: $!";
    print $fh $hexstamp;
    close $fh or die "close $tagfile: $!";
    DPSTD($model->getTag()." Updated $tagfile to $hexstamp");
    return 0;
}

sub pushDir {
    my __PACKAGE__ $self = shift || die;
    my $dir = shift || die;
    push @{$self->{mCurDir}}, $dir;
    return $dir;
}

sub popDir {
    my __PACKAGE__ $self = shift || die;
    die unless @{$self->{mCurDir}};
    return pop @{$self->{mCurDir}};
}

sub curDir {
    my __PACKAGE__ $self = shift || die;
    die unless @{$self->{mCurDir}};
    return $self->{mCurDir}->[-1];
}

sub changeDir {
    my __PACKAGE__ $self = shift || die;
    my $dir = shift || die;
    die unless @{$self->{mCurDir}};
    my $top = $self->curDir();
    $self->{mCurDir}->[-1] = $dir;
    return $top;
}

sub doSC_PUSHTMP {
    my __PACKAGE__ $self = shift || die;
    my $model = $self->{mModel} || die;
    my $tmptmp = "/tmp/$self->{mSlotName}-XXXXX";
    my $tmpdir = tempdir( $tmptmp );
    $self->pushDir($tmpdir);
    DPSTD($model->getTag()." -Pushed to $tmpdir");
    return 0;
}

sub doSC_UNZIPCD {
    my __PACKAGE__ $self = shift || die;
    my $slotname = $self->{mSlotName} || die;
    my $model = $self->{mModel} || die;
    my $cd = $self->curDir() || die;
    my $target = "$cd/zip";
    initDir($target) or die "Couldn't make $target: $!";

    my $cdmdir = $self->{mCDMDir} || die;
    my $mfzpath = $model->makePath() || die;
    DPSTD($model->getTag()." -Unpacking $mfzpath to $cd");
    my $ret = runCommandWithSync("${\PATH_PROG_MFZRUN} -kd $cdmdir $mfzpath unpack $target","INSTALL $slotname: ERROR");
    return $ret ? 0 : -1; # rCWS returns non-zero on success; we must die without that
}

# Find precisely one tar file inside unzipped mfz, untar it, ensure it
# creates one top-level directory in that process, and capture that
# directory name in {mTarDirName} and {mTarDirPath}.
sub doSC_UNTARCD {
    my __PACKAGE__ $self = shift || die;
    my $slotname = $self->{mSlotName} || die;
    my $model = $self->{mModel} || die;
    my $cd = $self->curDir() || die;
    my $target = "$cd/tar";
    initDir($target) or die "Couldn't make $target: $!";

    DPSTD($model->getTag()." -Finding tgz file in $cd");

    my $tgzpath;
    {
        my $cmd = "find $cd -name '*.tgz'";
        my $output = `$cmd`;
        chomp $output;
        DPSTD($model->getTag()." -Found ($output)");
        my @lines = split("\n",$output);
        my $count = scalar(@lines);
        if ($count != 1) {
            DPSTD($model->getTag()." -ABORT: FOUND $count LINES");
            return 1;  # Causes the configureSlot to end, rather than cdm to die
        }
        $tgzpath = $lines[0];
    }

    DPSTD($model->getTag()." -Unpacking $tgzpath to $target");

    my $ret = runCommandWithSync("tar xf $tgzpath -m --warning=no-timestamp -C $target","INSTALL $slotname: ERROR");
    return -1 if !$ret; # rCWS returns non-zero on success; we must die without that

    DPSTD($model->getTag()." -Checking for top-level dir");
    my @files = grep { $_ !~ /^[.]/ && -d "$target/$_" } listDir($target);
    DPSTD($model->getTag()." -Found [".join(", ",@files)."]");
    return -1 unless @files == 1;
    $self->{mTarDirName} = $files[0];
    $self->{mTarDirPath} = "$target/$files[0]";
    return 0;
}

# Back up destination dir, move unpacked tar dir to destination in target dir, cd to destination
sub doSC_TARTAR {
    my __PACKAGE__ $self = shift || die;
    my $slotname = $self->{mSlotName} || die;
    my $model = $self->{mModel} || die;
    my SlotConfig $sc = $self->{mSC} || die;
    my $targetdir = $sc->{mTargetDir} || die; # Don't come here without sc's target dir
    my $tardirname = $self->{mTarDirName} || die; # And don't confuse that with our tar
    my $tardirpath = $self->{mTarDirPath} || die; # dir name or our tar dir path doh

    my $dirtobackup = "$targetdir/$tardirname";
    if (-d $dirtobackup) {
        DPSTD($model->getTag()." -Found $dirtobackup");
        my $dirtobackupto = "$targetdir/$tardirname-prev-install";
        if (-d $dirtobackupto) {
            DPSTD($model->getTag()." -Deleting $dirtobackupto");
            my $count = remove_tree($dirtobackupto);
            DPSTD($model->getTag()." -Removed $count file".(($count!=1)?"s":""));
        }
        my $ret = runCommandWithSync("mv $dirtobackup $dirtobackupto","INSTALL $slotname: ERROR");
        return -1 if !$ret; # rCWS returns non-zero on success; we must die without that
        DPSTD($model->getTag()." -Renamed $dirtobackup -> $dirtobackupto");
    }
    die if -d $dirtobackup;

    DPSTD($model->getTag()." -Moving $tardirpath to $targetdir");
    my $ret = runCommandWithSync("mv $tardirpath $targetdir","INSTALL $slotname: ERROR");
    return -1 if !$ret; # rCWS returns non-zero on success; we must die without that
    DPSTD($model->getTag()." -Set up $tardirname in $targetdir");

    $self->{mInstallationDir} = "$targetdir/$tardirname";

    return 0;
}

sub doMakeCmdInDir {
    my __PACKAGE__ $self = shift || die;
    my $cmd = shift || die;
    my $indir = shift || die;
    my $slotname = $self->{mSlotName} || die;
    my $model = $self->{mModel} || die;
    my SlotConfig $sc = $self->{mSC} || die;
    -d $indir or die;
    DPSTD($model->getTag()." -Running 'make $cmd' in $indir");
    my $ret = runCommandWithSync("make -C $indir $cmd","INSTALL $slotname: ERROR");
    return -1 if !$ret; # rCWS returns non-zero on success; we must die without that
    DPSTD($model->getTag()." -Make $cmd succeeded");

    return 0;
}

sub doSC_INSTALL {
    my __PACKAGE__ $self = shift || die;
    my $installdir = $self->{mInstallationDir} || die; # Don't come here before SC_TARTAR works
    my $ret = $self->doMakeCmdInDir('install', $installdir);
    return $ret;
}

sub doSC_RESTART {
    my __PACKAGE__ $self = shift || die;
    my $installdir = $self->{mInstallationDir} || die; # Don't come here before SC_TARTAR works
    my $ret = $self->doMakeCmdInDir('restart', $installdir);
    return $ret;
}

sub doSC_REFRESH {
    my __PACKAGE__ $self = shift || die;
    my $installdir = $self->{mInstallationDir} || die; # Don't come here before SC_TARTAR works
    my $ret = $self->doMakeCmdInDir('refresh', $installdir);
    return $ret;
}

sub doSC_REBOOT  {
    die
}
sub doSC_CUSTOM  {
    die
}

1;
