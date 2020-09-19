## Module stuff
package SlotConfig;
use strict;
use fields qw(
    mSlotNum
    mLabel
    mTargetDir
    mActions
    mSubmissions
    );

use Exporter qw(import);

our @EXPORT_OK = qw(getSlotConfig);
our %EXPORT_TAGS;

## Imports
use Constants qw(:all);
use DP qw(:all);
use T2Utils qw(:all);
use MFZUtils qw(:all);
use MFZModel;
use CDM;

use File::Path qw(make_path);

my %SLOT_CONFIGS;

sub INIT_ALL_SLOTS {
    mSC(0x00,"deletions       ",undef,                 ,[SC_CUSTOM],[]);
    mSC(0x01,"T2Config        ","/home/t2/T2-12/config",[SC_INSTALL],[0x02]);
#    mSC(0x02,"T2-12           ","/home/t2/T2-12",       [SC_INSTALL,SC_REBOOT],[]);
#    mSC(0x03,"MFMT2           ","/home/t2/MFM",         [SC_INSTALL,SC_RESTART],[]);

    mSC(0x90,"TEST 90 ~/TEST90","/home/t2/TEST90",      [SC_INSTALL],[]);
}

##CLASS METHOD
sub getSlotConfig {
    my $slotnum = shift;
    defined $slotnum or die;
    $slotnum >= 0 && $slotnum <= 0xff or die;
    return $SLOT_CONFIGS{$slotnum};
}

##CLASS METHOD
sub configureMFZModel {
    my MFZModel $model = shift || die;

    my $ss = $model->{mSlotStamp} or die;
    my $slot = SSSlot($ss);
    my $sc = getSlotConfig($slot);
    return unless defined $sc;
    $sc->configureSlot($model);
}

##PRIVATE CLASS METHOD
sub mSC {  ## makeSlotConfig
    my ($slotnum, $label, $targetDir, $actions, $submissions) = @_;
    die "Duplicate $slotnum" if defined $SLOT_CONFIGS{$slotnum};
    my $sc = SlotConfig->new($slotnum);
    $sc->{mLabel} = trim($label || "");  # Fails if $label eq "0" so don't do that
    $sc->{mTargetDir} = $targetDir;      # or undef
    $sc->{mActions} = $actions || [];
    $sc->{mSubmissions} = $submissions || [];
    $SLOT_CONFIGS{$slotnum} = $sc;
    return $sc;
}

sub configureSlot {
    my __PACKAGE__ $self = shift || die;
    my MFZModel $model = shift || die;
    my CDM $cdm = $model->{mCDM} || die;
    die unless SSSlot($model->{mSlotStamp}) == $self->{mSlotNum};
    return DPSTD($model->getTag()." is not complete") unless $model->isComplete();
    my $mfzpath = $model->makePath();
    my $targetdir = $self->{mTargetDir};

    die unless -r $mfzpath;
    die unless -d $targetdir;

    my $cdmdir = $cdm->getBaseDirectory();
    my $tagdir = $cdmdir."/".SUBDIR_TAGS;
    unless (-d $tagdir) {
        make_path($tagdir)
            or die "Couldn't mkdir $tagdir: $!";
    }

    if (defined($targetdir)) {
        my $fn = $self->checkIfInstallable($model,$tagdir);
        return unless defined($fn); # message already offered
        my ($tgzpath, $targetsubdir) = installUnpack($cdm, $self->{mSlotNum},$mfzpath,$targetdir,$tagdir);
        return unless defined($targetsubdir);
    }
    die "XXXX FINASIFDKLSDL";
    
}


## CLASS METHOD
sub installUnpack {  # Unpack mfz into given targetdir
    my CDM $cdm = shift || die;
    my $slotnum = shift || die;
    my $mfzpath = shift || die;
    my $targetdir = shift || die;
    my $tagdir = shift || die;
    my $basename = sprintf("slot%02x",$slotnum);
    my $cdmdir = $cdm->getBaseDirectory();

    DPSTD("${\FUNCNAME} mfzp $mfzpath td $targetdir");

    ### DO UNPACK
    DPSTD("$mfzpath: Starting install");
    my $tmpdirname = "/tmp/$basename-cdm-install-tmp";
    DPSTD("$mfzpath: (1) Clearing $tmpdirname");

    return unless runCommandWithSync("rm -rf $tmpdirname","INSTALL $basename: ERROR");
    return unless runCommandWithSync("mkdir -p $tmpdirname","INSTALL $basename: ERROR");

    DPSTD("INSTALL $basename: (2) Unpacking");

    return unless runCommandWithSync("${\PATH_PROG_MFZRUN} -kd $cdmdir $mfzpath unpack $tmpdirname","INSTALL $basename: ERROR");

    DPSTD("INSTALL $basename: (3) Finding tgz");
    my $tgzpath;
    {
        my $cmd = "find $tmpdirname -name '*.tgz'";
        my $output = `$cmd`;
        chomp $output;
        DPSTD("INSTALL $basename: (3.1) GOT ($output)");
        my @lines = split("\n",$output);
        my $count = scalar(@lines);
        if ($count != 1) {
            DPSTD("INSTALL $basename: ABORT: FOUND $count LINES");
            return;
        }
        $tgzpath = $lines[0];
    }
    DPSTD("INSTALL $basename: (3.2) Using $tgzpath");

    my $targetsubdir = "$tmpdirname/cdmtgz";
    DPSTD("INSTALL $basename: (4) Clearing '$targetsubdir'");
    return unless runCommandWithSync("rm -rf $targetsubdir","INSTALL $basename: ERROR");
    return unless runCommandWithSync("mkdir -p $targetsubdir","INSTALL $basename: ERROR");

    DPSTD("INSTALL $basename: (5) Unpacking '$tgzpath' -> $targetsubdir");
    my $initialbasenamedir;
    return unless runCommandWithSync("tar xf $tgzpath -m --warning=no-timestamp -C $targetsubdir","INSTALL $basename: ERROR");

    DPSTD("HOW DO WE CHECK THAT THE $targetdir basename now appears at the top of $targetsubdir?");

    # $initialbasenamedir = "$targetsubdir/$basename";
    # if (!(-r $initialbasenamedir && -d $initialbasenamedir)) {
    #     DPSTD("INSTALL $basename: (5.1) ABORT: '$initialBaseNameDir' not readable dir");
    #     return;
    # }

    return ($tgzpath, $targetsubdir);
}

sub checkIfInstallable { # Check if MFZModel needs to be installed
    my __PACKAGE__ $self = shift || die;
    my MFZModel $model = shift || die;
    my $tagdir = shift || die;

    my $targetdir = $self->{mTargetDir};
    return DPSTD($model->getTag()." no installation configured")  # No target -> not installable
        unless defined $targetdir;

    unless (-e $targetdir) {
        make_path($targetdir)      
            or die "Couldn't mkdir $targetdir: $!";
    }
    die unless -d $targetdir;

    my $cdmap = $model->{mCDMap} || die;
    my $ss = $model->{mSlotStamp} || die;
    my $fn = SSToFileName($ss);
    my $slot = SSSlot($ss);
    my $stamp = SSStamp($ss);

    my $tagname = sprintf("%s/slot%02x-install-tag.dat", $tagdir, $slot);

    if (-r $tagname) {
        open my $fh,'<',$tagname or die "Can't read $tagname: $!";
        my $line = <$fh>;
        close $fh or die "close $tagname: $!";
        $line ||= "";
        chomp $line;
        if ($line !~ /^([0-9a-zA-Z]+)$/) {
            DPSTD("CHECK $fn: Ignoring malformed $tagname ($line)");            
        } else {
            my $currentstamp = hex($1);
            return DPSTD("CHECK $fn: We are up to date; nothing to do")
                if $stamp == $currentstamp;

            if ($stamp < $currentstamp) {
                DPSTD(sprintf("CHECK $fn: Candidate appears outdated (have %06x)", $currentstamp));
                DPSTD("CHECK $fn: NOT INSTALLING. Delete $tagname to allow this install");
                return;
            }
        }
        DPSTD("CHECK $fn: PROCEEDING");
    } 
    return $fn;
}

## Methods
sub new {
    my SlotConfig $self = shift;
    my $slotnum = shift; defined $slotnum or die;
    unless (ref $self) {
        $self = fields::new($self);
    }

    $self->{mSlotNum} = $slotnum;
    $self->{mLabel} = undef;
    $self->{mTargetDir} = undef;
    $self->{mActions} = undef;
    $self->{mSubmissions} = undef;
    return $self;
}

INIT_ALL_SLOTS();

1;
