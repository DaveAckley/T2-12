## Module stuff
package DirectoryManager;
use strict;
use base 'TimeoutAble';
use fields qw(
    mDirsMgr
    mDirectoryName
    mDirectoryPath
    mDirectoryModTime
    mPathsToLoad
    mMFZManagers
    );

use Exporter qw(import);

our @EXPORT_OK = qw();
our %EXPORT_TAGS;

## Imports
use File::Copy; # For move
use List::Util qw(shuffle);

use T2Utils qw(:all);

use DP qw(:all);

## Methods
sub new {
    my DirectoryManager $self = shift;
    my $dir = shift or die;
    my CDM $cdm = shift or die;
    my $dirsmgr = shift or die;
    unless (ref $self) {
        $self = fields::new($self); # really a class
    }
    $self->SUPER::new("DirMgr:$dir",$cdm);

    $self->{mDirsMgr} = $dirsmgr;
    $self->{mDirectoryName} = $dir;
    $self->{mDirectoryPath} = $self->{mDirsMgr}->getPathTo($self->{mDirectoryName});
    $self->{mDirectoryModTime} = -M $self->{mDirectoryPath};
    $self->{mPathsToLoad} = [];
    $self->{mMFZManagers} = {}; # Content name -> MFZManager

    $self->{mCDM}->getTQ()->schedule($self);

    return $self;
}

sub getRandomMFZMgr {
    my ($self) = @_;
    my @mfzms = values %{$self->{mMFZManagers}};
    my $idx = int(rand($#mfzms+1));
    return $mfzms[$idx];
}

sub getMFZMgr {
    my __PACKAGE__ $self = shift;
    my $contentName = shift or die;
    
    return $self->{mMFZManagers}->{$contentName};
}

sub insertMFZMgr {
    my __PACKAGE__ $self = shift or die;
    my MFZManager $mfzmgr = shift or die;
    $mfzmgr->isa('MFZManager') or die;
    die "MFZManager is already has dm" if defined $mfzmgr->{mDirectoryManager};
    my $name = $mfzmgr->{mContentName};
    die "Already have manager for $name" if defined $self->getMFZMgr($name);
    $self->{mMFZManagers}->{$name} = $mfzmgr;
    DPSTD("${\FUNCNAME} ${\$self->getTag()} inserted ($name)");
    $mfzmgr->{mDirectoryManager} = $self;
}

sub removeMFZMgr {
    my ($self,$mfzmgr) = @_;
    $mfzmgr->isa('MFZManager') or die;
    die if $mfzmgr->{mDirectoryManager} != $self;
    my $name = $mfzmgr->{mContentName};
    die unless defined $self->getMFZMgr($name);
    delete $self->{mMFZManagers}->{$name};
    $mfzmgr->{mDirectoryManager} = undef;
}

# Take control of an mfzmgr, moving the underlying file in the process
sub takeMFZAndFile {
    my __PACKAGE__ $self = shift or die;
    my MFZManager $tomove = shift or die;
    my DirectoryManager $dmfrom = $tomove->{mDirectoryManager} or die;
    my $cn = $tomove->{mContentName} or die;
    return DPSTD("${\$self->getTag()} ignoring move to self for $cn")
        if $self == $dmfrom;
    my $todir = $self->{mDirectoryPath};
    my $movingpath = $tomove->getPathToFile();
    move($movingpath,$todir) or die "File move $movingpath => $todir failed: $!";
    $dmfrom->removeMFZMgr($tomove);
    $self->insertMFZMgr($tomove);
    DPSTD("$cn moved to $todir");
}

sub reloadPaths {
    my __PACKAGE__ $self = shift or die;
    my $dirpath = $self->{mDirectoryPath};
    if (!opendir(DIR, $dirpath)) {
        DPSTD("WARNING: Can't load $dirpath: $!");
    } else {
        @{$self->{mPathsToLoad}} = grep { /[.]mfz$/ } shuffle readdir DIR;
        closedir DIR or die "Can't close $dirpath: $!\n";
    }
        
    return scalar(@{$self->{mPathsToLoad}});
}

sub considerAPath {
    my __PACKAGE__ $self = shift or die;
    my $nextname = shift @{$self->{mPathsToLoad}};
    if (defined($nextname)) {
        DPDBG("CONSIDERING $nextname");
        if (!defined($self->{mMFZManagers}->{$nextname})) {
            $self->newContent($nextname);
            return 1;
        }
    }
    return 0;
}

sub loadAll {
    my __PACKAGE__ $self = shift or die;
    $self->reloadPaths();
    while ($self->considerAPath() != 0) { }
}

sub update {
    my ($self) = @_;
    my $dirpath = $self->{mDirectoryPath};
    my $modtime = -M $dirpath;
    my $forced;
    
    if ($modtime != $self->{mDirectoryModTime}) {
        DPSTD("MODTIME CHANGE ON $dirpath");
        $self->{mDirectoryModTime} = $modtime;
        @{$self->{mPathsToLoad}} = ();  # Force reload
        $forced = 1;
    }

    if (scalar(@{$self->{mPathsToLoad}}) == 0) {
        if ($self->reloadPaths() == 0) { # Screw it if still nothing
            $self->reschedule(-20);
        } else {
            DPSTD(scalar(@{$self->{mPathsToLoad}}). " file(s) to consider") if $forced;
            $self->reschedule(-2);
        }
        return 1; # Refilled mPathsToLoad
    }

    if ($self->considerAPath()) {
        $self->reschedule(-2);
        return 1;
    } else {
        $self->reschedule(-20);
        return 0;
    }
    return 1; # 'Did something'?
}

sub reportMFZStats {
    my __PACKAGE__ $self = shift;
    my @cns = sort keys %{$self->{mMFZManagers}};
    my $maxlen = 16;
    my @ret = ();
    for my $cn (@cns) {
        my $mgr = $self->{mMFZManagers}->{$cn};
        my $len = $mgr->getCurrentLength();
        my $totlen = $mgr->{mFileTotalLength};
        push @ret,
            sprintf(" %4s %4s %*s\n",
                    $totlen > 0 ? formatPercent(100.0*$len/$totlen) : "-- ",
                    formatSize($len),
                    -$maxlen, substr($cn,0,$maxlen));
    }
    return @ret;
}

## VIRTUAL
sub notifyTransferManagers {
    my __PACKAGE__ $self = shift or die;
    my MFZManager $mgr = shift or die;
    ## BASE CLASS DOES NOTHING
}

## VIRTUAL
sub newContent {
    my __PACKAGE__ $self = shift;
    my $cname = shift or die;
    ## Subclasses should create an appropriate MFZManager for $cname
    ## and insert it in self (appropriately).
   die ("Not overridden: newContent $cname");
}

sub onTimeout {
    my ($self) = @_;
    DPPushPrefix($self->getTag());
    $self->update();
    DPPopPrefix(); 
}

1;
