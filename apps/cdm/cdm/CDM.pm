## Module stuff
package CDM;
use strict;
use fields qw(
    mPrograms 
    mTimeQueue 
    mPacketIO
    mDirectoriesManager
    mNeighborhoodManager
    mTraditionalManager
    mPipelineManager
    mHookManager
    mStatusReporter
    mCryptoManager
);

use Exporter qw(import);

our @EXPORT_OK = qw();
our %EXPORT_TAGS;

## Imports
# Our classes
use Constants qw(:all);
use T2Utils qw(:all);
use DP qw(:functions :flags);

use MFZManager;
use TimeQueue;
use DirectoriesManager;
use DMCommon;
use DMPending;
use DMPipeline;
use PacketIO;
use NeighborhoodManager;
use TMTraditional;
use TMPipeline;
use HookManager;
use StatusReporter;
use CryptoManager;

# Other imports
use Fcntl;
use Errno qw(EAGAIN);
use Time::HiRes qw(sleep);
use List::Util qw/shuffle/;
use Digest::SHA qw(sha512_hex);
use DateTime::Format::Strptime;

sub new {
    my CDM $self = shift;
    my $base = shift or die;
    -d $base or die "'$base' is not a directory";
    unless (ref $self) {
        $self = fields::new($self);
    }
    $self->{mPrograms} = {
        mMfzrun => "/home/t2/MFM/bin/mfzrun"        
    };
    $self->{mTimeQueue} = TimeQueue->new();
    $self->{mDirectoriesManager} = DirectoriesManager->new($self,$base);
    $self->{mHookManager} = HookManager->new($self);
    return $self;
}

sub getTQ {
    my ($self) = @_;
    return $self->{mTimeQueue};
}

sub getBaseDirectory {
    return shift->getDirectoriesManager()->getBaseDirectory();
}

sub getDirectoriesManager {
    my __PACKAGE__ $self = shift or die;
    return $self->{mDirectoriesManager};
}

sub schedule {
    my ($self,$to,$delay) = @_;
    $to->isa("TimeoutAble") or die;
    $self->{mTimeQueue}->schedule($to,$delay);
}

sub eventLoop {
    my ($self) = @_;
    while (1) {
        my $next = $self->{mTimeQueue}->runEvent();
        sleep(max($next,0.05));
    }
}

sub init {
    my __PACKAGE__ $self = shift or die;
    $self->{mDirectoriesManager}->init();
    Hooks::installHooks($self);

    $self->createTasks();
}

sub getPIO {
    my __PACKAGE__ $self = shift;
    die unless defined $self->{mPacketIO};
    return $self->{mPacketIO};
}

sub createTasks {
    my ($self) = @_;

    die if defined $self->{mCryptoManager};
    $self->{mCryptoManager} = CryptoManager->new($self,undef); # default -kd
    $self->{mCryptoManager}->init();

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

    die if defined $self->{mStatusReporter};
    $self->{mStatusReporter} = StatusReporter->new($self);
    $self->{mStatusReporter}->init();

#    my $demo = MFZManager->new("DEMO",$self);
#    $self->{mInPipelineContent}->insertMFZMgr($demo);
}

# sub checkCommonFile {
#     my ($self, $announce) = @_;
#     die;
# }

# sub preinitCommon {
#     my ($self) = @_;
#     DPSTD("Preloading common");
#     my $count = 0;
#     while ($self->checkCommonFile(0)) {
#         ++$count; 
#     }
#     DPVRB("Preload complete after $count steps");
# }

# sub getITCDirNames {
#     return sort { $ITCDirs{$a} <=> $ITCDirs{$b} } keys %ITCDirs;
# }

# sub getITCDirIndex {
#     my ($self, $dir) = @_;
#     return $ITCDirs{$dir};
# }

1;
