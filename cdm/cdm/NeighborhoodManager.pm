## Module stuff
package NeighborhoodManager;
use strict;
use base 'TimeoutAble';
use fields qw(
    mNeighbors
    mITCStatusHandle
    );

use Exporter qw(import);

our @EXPORT_OK = qw();
our %EXPORT_TAGS;

## Imports
use Fcntl;
use IO::Handle;
use List::Util qw(shuffle);

use DP qw(:all);
use T2Utils qw(:all);
use Constants qw(:all);
use NeighborManager;

use constant ITC_STATUS_DEVICE => "/sys/class/itc_pkt/status";
use constant ITC_STATUS_MODE => O_RDONLY;

## Methods
sub new {
    my ($class,$cdm) = @_;
    defined $cdm or die;
    my $self = fields::new($class);
    $self->SUPER::new("HoodMgr",$cdm);

    $self->{mNeighbors} = []; # NeighborManager by dir6
    open($self->{mITCStatusHandle}, "<", ITC_STATUS_DEVICE) or die;

    $self->{mCDM}->getTQ()->schedule($self);
    $self->defaultInterval(-20); # Run about every 10 seconds if nothing happening

    return $self;
}

sub init {
    my ($self) = @_;
    my $cdm = $self->{mCDM};
    die if scalar($self->getNgbMgrs()) > 0;
    DPSTD("Init ngbs");
    for my $dir6 (getDir6s()) {
        my $ngb = NeighborManager->new($dir6,$cdm);
        $self->{mNeighbors}->[$dir6] = $ngb;
    }
}

sub ngbMgr {
    my ($self, $dir6) = @_;
    my @mgrs = $self->getNgbMgrs();
    return $mgrs[$dir6];
}

sub getRandomOpenNgbMgr {
    my ($self) = @_;
    my @openmgrs = grep { $_->state() >= NGB_STATE_OPEN } $self->getNgbMgrs();
    return pickOne(@openmgrs);
}

sub getNgbMgrs {
    my ($self) = @_;
    return @{$self->{mNeighbors}};
}

sub updateStatus {
    my ($self) = @_;
    my $hdl = $self->{mITCStatusHandle};
    seek($hdl,0,0);
    my $stat = <$hdl>;
    chomp $stat;
    my @bytes = reverse split(//,$stat);
    if (scalar(@bytes) != 8) {
        DPSTD("Bad status '$stat'");
        return;
    }
    for my $dir6 (dir6Iterator()) {
        my $dir8 = mapDir6ToDir8($dir6);
        my $byte = $bytes[$dir8];

        my $nbmg = $self->ngbMgr($dir6);
        $nbmg->acceptStatus(0+$byte);
    }
}

sub update {
    my ($self) = @_;

    $self->updateStatus();
    # my $dirpath = $self->{mNeighborhoodPath};
    # my $modtime = -M $dirpath;
    # my $forced;
    
    # if ($modtime != $self->{mNeighborhoodModTime}) {
    #     DPSTD("MODTIME CHANGE ON $dirpath");
    #     $self->{mNeighborhoodModTime} = $modtime;
    #     @{$self->{mPathsToLoad}} = ();  # Force reload
    #     $forced = 1;
    # }

    # if (scalar(@{$self->{mPathsToLoad}}) == 0) {
    #     if (!opendir(DIR, $dirpath)) {
    #         DPSTD("WARNING: Can't load $dirpath: $!");
    #     } else {
    #         @{$self->{mPathsToLoad}} = grep { /[.]mfz$/ } shuffle readdir DIR;
    #         closedir DIR or die "Can't close $dirpath: $!\n";
    #     }
        
    #     if (scalar(@{$self->{mPathsToLoad}}) == 0) { # Screw it if still nothing
    #         $self->reschedule(-20);
    #     } else {
    #         DPSTD(scalar(@{$self->{mPathsToLoad}}). " file(s) to consider") if $forced;
    #         $self->reschedule(-2);
    #     }
    #     return 0; # Did nothing of significance
    # }

    # my $nextname = shift @{$self->{mPathsToLoad}};
    # DPDBG("CONSIDERING $nextname");
    # if (!defined($self->{mMFZManagers}->{$nextname})) {
    #     $self->newContent($nextname);
    #     $self->reschedule(-2);
    # } else {
    #     $self->reschedule(-20);
    # }
    $self->reschedule(-10);
    return 1; # 'Did something'?
}

sub newContent {
    my ($self,$nextname) = @_;
    DPDBG("newContent $nextname");
}

sub onTimeout {
    my ($self) = @_;
    DPPushPrefix($self->getTag());
    $self->update();
    DPPopPrefix(); 
}

1;
