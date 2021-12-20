## Module stuff
package NeighborManager;
use strict;
use base 'TimeoutAble';
use fields qw(
    mDir6
    mDirName
    mDir8
    mITCStatus
    mState
    mTheirVersion
    mLastSentTime
    mLastRecvTime
    mPacketIO
    mRollingTag
    );

use Exporter qw(import);

our @EXPORT_OK = qw();
our %EXPORT_TAGS;

## Imports
use List::Util qw(shuffle);

use T2Utils qw(:all);
use DP qw(:all);
use TimeQueue;
use Constants qw(:all);
use PacketClasses;

## Methods
sub new {
    my ($class,$dir6,$cdm) = @_;
    defined $cdm or die;
    my $self = fields::new($class);
    my $dirname = getDir6Name($dir6);
    $self->SUPER::new("Ngb$dirname",$cdm);
    $self->{mDir6} = $dir6;
    $self->{mDirName} = $dirname;
    $self->{mDir8} = mapDir6ToDir8($dir6); # convenience
    $self->reset();

    return $self;
}

sub reset {
    my ($self) = @_;
    $self->{mState} = NGB_STATE_INIT;
    $self->{mTheirVersion} = CDM_PROTOCOL_VERSION_UNKNOWN;
    $self->{mITCStatus} = -1;  # Set by NeighborhoodManager::update
    $self->{mLastSentTime} = undef; 
    $self->{mLastRecvTime} = undef; 
    $self->{mPacketIO} = undef;
    $self->{mRollingTag} = int(rand(100));
    
    $self->{mCDM}->getTQ()->schedule($self);
    $self->defaultInterval(-2);
}

sub theirVersion {
    my $self = shift;
    if (defined $_[0]) {
        my $ver = shift;
        if ($ver != $self->{mTheirVersion}) {
            DPSTD($self->getTag(). " IS VERSION $ver");
            $self->{mTheirVersion} = $ver;
        }
    }
    return $self->{mTheirVersion};
}

sub isOpen {
    my __PACKAGE__ $self = shift || die;
    return $self->state() >= NGB_STATE_OPEN;
}

sub acceptStatus { # 0:disabled, 1:enabled but no mfz compat, 2:mfz compat known
    my ($self,$status) = @_;
    if ($status == 0 && $self->state() > NGB_STATE_INIT) {
        DPSTD($self->getTag()." ".$self->state()." => ".NGB_STATE_INIT);
        $self->reset(); # Force retraining
        {
            # Tell Urgency the bad news
            my $urg = $self->{mCDM}->getUrgencyManager();
            $urg->forgetAboutThem($self->{mDir8});
        }
            
    } elsif ($status > 0 && $self->state() < NGB_STATE_OPEN) {
        DPSTD($self->getTag()." STATUS CHANGE ".$self->state()." => ".NGB_STATE_OPEN);
        $self->state(NGB_STATE_OPEN);
        $self->reschedule();
    }
}

sub state {
    my $self = shift;
    $self->{mState} = shift if defined $_[0];
    return $self->{mState};
}

sub processCmdTypeA {
    my ($self,$rest) = @_;
    # $rest starts with byte[3] of packet
    # if length($rest) <= 1 theirversion == 1
    # if length($rest) >= 2 theirversion = byte[4] AKA $rest[1]
    DPSTD("TYPEA REST($rest)");
    $self->theirVersion(length($rest) <= 1 ? 1 : ord(substr($rest,1,1)));
    return 1;
}

sub bump {
    my ($self) = @_;
    $self->{mLastRecvTime} = $self->{mCDM}->getTQ()->now();
}

sub considerInboundCDM {
    my ($self,$cmd,$rest) = @_;
    $self->{mLastRecvTime} = $self->{mCDM}->getTQ()->now();
    #DPSTD("CICDM $cmd/$rest");

    ## HANDLE TYPE A 
    return $self->processCmdTypeA($rest)
        if $cmd eq "A";

    ## EAT TYPE P UNLESS NEW PIPELINE
    return 1
        if $cmd eq "P" && $self->theirVersion() < 3;

    ## EAT TYPE FCD UNLESS HAS VERSION
    return 1
        if ($cmd eq "F" || $cmd eq "C" || $cmd eq "D")
        && $self->theirVersion() < 1;

    DPSTD($self->getTag()." Consider handling $cmd +".length($rest));
    return 0;
}

sub isLive {
    my ($self) = @_;
    
}

sub init {
    my ($self) = @_;
    my $cdm = $self->{mCDM};
}

sub getPIO {
    my ($self) = @_;
    $self->{mPacketIO} = $self->{mCDM}->{mPacketIO}
    unless defined $self->{mPacketIO};
    die unless defined $self->{mPacketIO};
    return $self->{mPacketIO};
}

sub sendVersion {
    my ($self) = @_;
    return 0 unless $self->state() >= NGB_STATE_OPEN;

    my PacketCDM_A $pkt = PacketCDM_A->new();
    $pkt->setDir8($self->{mDir8});
    $pkt->setOptVersion(CDM_PROTOCOL_OUR_VERSION);
    $pkt->{mRollingTag} = ($self->{mRollingTag}&0xff);

    my $pio = $self->getPIO();
    if ($pkt->sendVia($pio)) {
        $self->{mLastSentTime} = now();
        $self->{mRollingTag}++;
        return 1;
    }
DPSTD($self->getTag()." sv($pio) NO");
    return undef;
}

sub considerSendingVersion {
    my ($self) = @_;
    if (!defined($self->{mLastSentTime}) || aged($self->{mLastSentTime},60)) {
        return $self->sendVersion();
    }
    return 0;
}

sub update {
    my ($self) = @_;
    return 1
        if $self->considerSendingVersion();
}

sub onTimeout {
    my ($self) = @_;
    DPPushPrefix($self->getTag());
    $self->update();
    DPPopPrefix(); 
}

1;
