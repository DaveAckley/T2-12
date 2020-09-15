## Module stuff
package DirectoriesManager;
use strict;
use base 'TimeoutAble';
use fields qw(
    mBaseDirectory
    mCompleteAndVerifiedContent
    mInPipelineContent
    );

use Exporter qw(import);

our @EXPORT_OK = qw();
our %EXPORT_TAGS;

## Imports
use Fcntl;
use IO::Handle;
use List::Util qw(shuffle);
use File::Path qw(make_path remove_tree);
use File::Basename;
use File::Copy qw(move copy);

use DP qw(:all);
use T2Utils qw(:all);
use Constants qw(:all);
#use DMCommon;
#use DMPending;
#use DMPipeline;

my @subdirs = (
    SUBDIR_COMMON,
    SUBDIR_LOG,
    SUBDIR_PIPELINE,
    SUBDIR_PUBKEY
    );
my @tmpsubdirs = (
    );

## Methods
sub new {
    my ($class,$cdm,$basedir) = @_;
    defined $basedir or die;
    my $self = fields::new($class);
    $self->SUPER::new("DirsMgr",$cdm);

    $self->{mBaseDirectory} = $basedir;
    $self->{mCompleteAndVerifiedContent} = undef;
    $self->{mInPipelineContent} = undef;

    $self->{mCDM}->getTQ()->schedule($self);
    $self->defaultInterval(-20); # Run about every 10 seconds if nothing happening

    return $self;
}

sub init {
    my __PACKAGE__ $self = shift or die;
    my CDM $cdm = $self->{mCDM};
    $self->checkInitDirectory($self->{mBaseDirectory}) or die;
    $self->flushTempDirectories();
    $self->checkInitDirectories();

#    $self->{mCompleteAndVerifiedContent} = DMCommon->new($cdm,$self);
#    $self->{mInPipelineContent} = DMPipeline->new($cdm,$self);
}

sub flushTempDirectories {
    my ($self) = @_;
    for my $tmp (@tmpsubdirs) {
        my $path = $self->getPathTo($tmp);
        my $count = remove_tree($path);
        DPSTD("Flushed $count $path files")
            if $count > 1;
    }

}

sub checkInitDirectory {
    my ($self,$dir) = @_;
    if (-d $dir) {
        DPSTD("Found $dir");
        return 1;
    }
    if (-e $dir) {
        DPSTD("$dir exists but is not a directory");
        return 0;
    }
    if (make_path($dir)) {
        DPSTD("Made $dir");
        return 1;
    }
    return 0;
}

sub checkInitDirectories {
    my ($self,$dir) = @_;

    foreach my $sub (@subdirs) {
        my $path = $self->getPathTo($sub);
        if (!$self->checkInitDirectory($path)) {
            die "Problem with '$path'";
        }
    }

    # Ensure our base key is in there
    my $keyPath = $self->getPathTo(SUBDIR_PUBKEY)."/t2%2dkeymaster%2drelease%2d10.pub";
    if (!(-e $keyPath)) {
        DPSTD("Initting $keyPath");;
        open HDL,">",$keyPath or die "Can't write $keyPath: $!";
        print HDL <<'EOF';
[MFM-Handle:t2-keymaster-release-10]
-----BEGIN RSA PUBLIC KEY-----
MIGJAoGBAMUbUl/GDrkKYB3ORkeetZEkKisfgiwl6TgoqAB7dfK1gGN3bzDyz/+A
LisTyW0b+64ePqv1liBxJEBOd2eX9+hTnngasOrb8RIQN6vTPg6+3WGAmgtez3kg
5KSeBLlgMaEbKkeOXZU+pbAaUzL6EGr/O/ESdTE6Lh6azq2DR3P7AgMBAAE=
-----END RSA PUBLIC KEY-----
EOF
      close HDL or die "Close $keyPath: $!";
    }
}

#    shift if ref $_[0] eq CDM;
sub getPathToCommon { shift->getPathTo(SUBDIR_COMMON); }
sub getPathToLog { shift->getPathTo(SUBDIR_LOG); }
sub getPathToPipeline { shift->getPathTo(SUBDIR_PIPELINE); }
sub getPathToPubkey { shift->getPathTo(SUBDIR_PUBKEY); }

sub getBaseDirectory {
    shift->{mBaseDirectory};
}

sub getPathTo {
    my ($self,$sub) = @_;
    defined $sub or die;
    return $self->getBaseDirectory()."/".$sub;
}

sub getDMCommon {
    my __PACKAGE__ $self = shift;
    return $self->{mCompleteAndVerifiedContent};
}

sub getDMPipeline {
    my __PACKAGE__ $self = shift;
    return $self->{mInPipelineContent};
}

sub getMFZManagerCNV {
    my ($self,$contentName) = @_;
    my $ret = $self->{mCompleteAndVerifiedContent}->{$contentName};
    return $ret;
}

sub getMFZManagerIPL {
    my ($self,$contentName) = @_;
    my $ret = $self->{mInPipelineContent}->{$contentName};
    return $ret;
}

# sub loadCommon {
#     my __PACKAGE__ $self = shift or die;
#     my $commonPath = $self->getPathToCommon();
#     if (!opendir(COMMON, $commonPath)) {
#         DPSTD("WARNING: Can't load $commonPath: $!");
#         return;
#     }
#     my @pathsToLoad = grep { /[.]mfz$/ } shuffle readdir COMMON;
#     closedir COMMON or die "Can't close $commonPath: $!\n";
    
# }

sub getDMs {
    my __PACKAGE__ $self = shift or die;
    return (  # In 'desirability' order..
        $self->{mCompleteAndVerifiedContent},
        $self->{mInPipelineContent}
        );
}

my %doms = (
    SUBDIR_COMMON => 2, # best
    SUBDIR_PIPELINE => 1, # better
);

sub getDominantDM {
    my __PACKAGE__ $self = shift or die;
    my $cn = shift or die;
    my @dms = $self->getDMs();
    my $windm;
    my $winmfzmgr;
    my $wintime = undef;
    for my $dm (@dms) {
        my $mfzmgr = $dm->getMFZMgr($cn);
        next unless defined $mfzmgr;
        my $time = $mfzmgr->{mFileInnerTimestamp};
        if (!defined($time) || $time < 0) {
            DPSTD("Unset time in $dm->{mDirectoryName} for ".$mfzmgr->getTag());
            next;
        }
        if (!defined($wintime) || $time > $wintime) {
            $wintime = $time;
            $winmfzmgr = $mfzmgr;
            $windm = $dm;
        } elsif ($time == $wintime &&
                 $doms{$dm->{mDirectoryName}} > $doms{$windm->{mDirectoryName}}) {
            $windm = $dm;
            $winmfzmgr = $mfzmgr;
        }
    }
    return ($windm,$winmfzmgr); # (undef,undef) or (not,not)
}

sub update {
    my __PACKAGE__ $self = shift or die;

    DPSTD("NNNNNNNNNNNNEEEEEEP");
    return 1; # 'Did something'?
}

sub onTimeout {
    my ($self) = @_;
    DPPushPrefix($self->getTag());
    $self->update();
    DPPopPrefix(); 
}

1;
