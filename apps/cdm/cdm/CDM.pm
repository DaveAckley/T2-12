## Module stuff
package CDM;
use strict;
use fields qw(
    mBaseDirectory
    mPrograms 
    mTimeQueue 
    mCompleteAndVerifiedContent
    mPendingContent
    mInPipelineContent
    mPacketIO
    mNeighborhoodManager
    mTraditionalManager
    mPipelineManager
    mHookManager
);

use Exporter qw(import);

our @EXPORT_OK = qw();
our %EXPORT_TAGS;

## Imports
# Our classes
use Constants qw(:all);
use DP qw(:functions :flags);
use MFZManager;
use TimeQueue;
use DMCommon;
use DMPending;
use DMPipeline;
use PacketIO;
use NeighborhoodManager;
use TMTraditional;
use TMPipeline;
use HookManager;

# Other imports
use Fcntl;
use File::Path qw(make_path remove_tree);
use File::Basename;
use File::Copy qw(move copy);
use Errno qw(EAGAIN);
use Time::HiRes;
use List::Util qw/shuffle/;
use Digest::SHA qw(sha512_hex);
use DateTime::Format::Strptime;

my @subdirs = (
    SUBDIR_COMMON,
    SUBDIR_LOG,
    SUBDIR_PENDING,
    SUBDIR_PIPELINE,
    SUBDIR_PUBKEY
    );
my @tmpsubdirs = (
    SUBDIR_PENDING,
    SUBDIR_PIPELINE,
    );

sub new {
    my CDM $self = shift;
    my $base = shift or die;
    -d $base or die "'$base' is not a directory";
    unless (ref $self) {
        $self = fields::new($self);
    }
    $self->{mBaseDirectory} = $base;
    $self->{mPrograms} = {
        mMfzrun => "/home/t2/MFM/bin/mfzrun"        
    };
    $self->{mTimeQueue} = TimeQueue->new();
    $self->{mCompleteAndVerifiedContent} = DMCommon->new($self);
    $self->{mPendingContent} = DMPending->new($self);
    $self->{mInPipelineContent} = DMPipeline->new($self);
    $self->{mHookManager} = HookManager->new($self);
    return $self;
}

sub getTQ {
    my ($self) = @_;
    return $self->{mTimeQueue};
}

sub getDMCommon {
    my __PACKAGE__ $self = shift;
    return $self->{mCompleteAndVerifiedContent};
}

sub getDMPending {
    my __PACKAGE__ $self = shift;
    return $self->{mPendingContent};
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

sub schedule {
    my ($self,$to,$delay) = @_;
    $to->isa("TimeoutAble") or die;
    $self->{mTimeQueue}->schedule($to,$delay);
}

sub eventLoop {
    my ($self) = @_;
    while (1) {
        my $next = $self->{mTimeQueue}->runExpired();
        sleep ($next >= 0 ? $next : 1);
    }
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
sub getPathToPending { shift->getPathTo(SUBDIR_PENDING); }
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

sub init {
    my ($self) = @_;
    $self->checkInitDirectory($self->{mBaseDirectory}) or die;
    $self->flushTempDirectories();
    $self->checkInitDirectories();
    $self->createTasks();
}

sub loadCommon {
    my ($self) = @_;
    my $commonPath = $self->getPathToCommon();
    if (!opendir(COMMON, $commonPath)) {
        DPSTD("WARNING: Can't load $commonPath: $!");
        return;
    }
    my @pathsToLoad = grep { /[.]mfz$/ } shuffle readdir COMMON;
    closedir COMMON or die "Can't close $commonPath: $!\n";
    
}

sub getPIO {
    my __PACKAGE__ $self = shift;
    die unless defined $self->{mPacketIO};
    return $self->{mPacketIO};
}

sub createTasks {
    my ($self) = @_;

    die if defined $self->{mPacketIO};
    $self->{mPacketIO} = PacketIO->new($self);
    $self->{mPacketIO}->init();

    die if defined $self->{mNeighborhoodManager};
    $self->{mNeighborhoodManager} = NeighborhoodManager->new($self);
    $self->{mNeighborhoodManager}->init();

    die if defined $self->{mTraditionalManager};
    $self->{mTraditionalManager} = TMTraditional->new($self);
    $self->{mTraditionalManager}->init();

    die if defined $self->{mPipelineManager};
    $self->{mPipelineManager} = TMPipeline->new($self);
    $self->{mPipelineManager}->init();

#    my $demo = MFZManager->new("DEMO",$self);
#    $self->{mInPipelineContent}->insertMFZMgr($demo);
}

sub checkCommonFile {
    my ($self, $announce) = @_;
    die;
}

sub preinitCommon {
    my ($self) = @_;
    DPSTD("Preloading common");
    my $count = 0;
    while ($self->checkCommonFile(0)) {
        ++$count; 
    }
    DPVRB("Preload complete after $count steps");
}

# sub getITCDirNames {
#     return sort { $ITCDirs{$a} <=> $ITCDirs{$b} } keys %ITCDirs;
# }

# sub getITCDirIndex {
#     my ($self, $dir) = @_;
#     return $ITCDirs{$dir};
# }

1;
