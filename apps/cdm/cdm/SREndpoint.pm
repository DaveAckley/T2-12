## Module stuff
package SREndpoint;
use strict;
use strict 'refs';
use base 'TimeoutAble';
use fields qw(
    mSRManager
    mLineBuffer
    mIsClient
    mToCoord
    mRoute
    mUserHandle
    mRetryCount
    mLastActivity
    mOurStartSeqno
    mTheirStartSeqno
    mXmitData
    mRecvData
    mNeedToAck
    );

use Exporter qw(import);

our @EXPORT_OK = qw();
our %EXPORT_TAGS;

## Imports
use Socket;
use IO::Select;
use IO::Socket::UNIX;

use List::Util qw(shuffle);

use T2Utils qw(:all);
use MFZUtils qw(:all);
use DP qw(:all);
use TimeQueue;
use Constants qw(:all);
use PacketClasses;
use PacketSR;
use PacketSR_C;
use PacketSR_Qq;

use DataQueue;

## Methods
sub new {
    my ($class,$cdm) = @_;
    defined $cdm or die;
    my $self = fields::new($class);
    $self->SUPER::new("SREndpoint",$cdm);
    $self->{mSRManager} = undef;    # Illegal value
    $self->{mLineBuffer} = undef;   # Illegal value
    $self->{mIsClient} = undef;     # Illegal value
    $self->{mToCoord} = undef;      # Illegal value
    $self->{mRoute} =  undef;       # Illegal value
    $self->{mUserHandle} =  undef;  # Until local connection is accepted
    $self->{mRetryCount} = -1;      # Illegal value
    $self->{mLastActivity} = -1;    # Illegal value
    $self->{mOurStartSeqno} = -1;   # -1 => Uninitted, 0 => Closed, >0 => Open
    $self->{mTheirStartSeqno} = -1; # -1 => Uninitted, 0 => Closed, >0 => Open
    $self->{mXmitData} = undef; # Illegal value
    $self->{mRecvData} = undef;  # Illegal value
    $self->{mNeedToAck} = undef;

    $self->{mCDM}->getTQ()->schedule($self);
    $self->defaultInterval(-2);
    return $self;
}

sub init {
    my __PACKAGE__ $self = shift || die;
    my $cdm = $self->{mCDM};

    die "REINIT?" if defined $self->{mSRManager};
    $self->{mSRManager} = $cdm->{mSRManager} or die;
    $self->{mLineBuffer} = "";  # Nothing buffered
    $self->{mRetryCount} = 0;
}

sub connectLocal {
    my __PACKAGE__ $self = shift || die;
    my $fh = shift || die;

    die "RECONNECT LOCAL?" if $self->{mOurStartSeqno} >= 0;
    $self->{mUserHandle} = $fh;
    $self->{mOurStartSeqno} = createNBits(16)|1;  # We're not wrapping so don't blow whole range
    DPSTD(sprintf("LOCAL CONNECT %s %d",
                  fileno($self->{mUserHandle}),
                  $self->{mOurStartSeqno}));
}

sub disconnectLocal {
    my __PACKAGE__ $self = shift || die;
    DPSTD(sprintf("LOCAL DISCONNECT %s %08x",
                  fileno($self->{mUserHandle}),
                  $self->{mOurStartSeqno}));
    $self->{mOurStartSeqno} = 0;
    $self->{mUserHandle} = undef;
}

sub disconnectNetwork {
    my __PACKAGE__ $self = shift || die;
    $self->{mTheirStartSeqno} = 0;
}

sub isClosedLocal {
    my __PACKAGE__ $self = shift || die;
    return $self->{mOurStartSeqno} <= 0;
}

sub isClosedNetwork {
    my __PACKAGE__ $self = shift || die;
    return $self->{mTheirStartSeqno} <= 0;
}

sub isFullyClosed {
    my __PACKAGE__ $self = shift || die;
    return
        $self->isClosedLocal() &&
        $self->isClosedNetwork();
}

sub connectNetwork {
    my __PACKAGE__ $self = shift || die;
    my $theirstartseqno = shift || die;
    die unless
        $theirstartseqno > 0 &&
        $theirstartseqno < (1<<32);

    die "RECONNECT NET?" if defined $self->{mTheirStartSeqno} >= 0;
    $self->{mTheirStartSeqno} = $theirstartseqno;
}

sub configureRoute {
    my __PACKAGE__ $self = shift || die;
    my $configline = shift || die;
    chomp $configline;
    my $fh = $self->{mUserHandle} || die;
    die if defined $self->{mRoute};

    my ($to,$here,$from) = unpackRoute($configline);
    return $self->{mSRManager}->closeLocal($fh,"Bad route '$configline'")
        unless defined $from;
    return $self->{mSRManager}->closeLocal($fh,"In-transit route '$configline' illegal")
        unless atStartOfRoute($configline) || atEndOfRoute($configline);
    return $self->{mSRManager}->closeLocal($fh,"Route too long '$configline'")
        unless length($configline) <= 32; # ?? That's a long route.  Better think about relays bro
    
    $self->{mRoute} = $configline;
    $self->{mIsClient} = atStartOfRoute($configline);
    my ($x,$y) = collapseRouteToCoord($configline);
    $self->{mToCoord} = packCoord($x,$y);
    my $fileno = fileno($fh);
    my $srm = $self->{mSRManager};
    $srm->registerClientServer($self);
    DPSTD("CONFIG '$configline' LOCAL $fileno, ($self->{mIsClient},$x,$y)");

    $self->{mXmitData} = DataQueue->new($self->{mCDM});
    if ($self->{mIsClient}) {
        $self->{mXmitData}->init($configline,  # client xmits on its talking route
                                 $self->{mOurStartSeqno},
                                 "D");
    } else {
        $self->{mXmitData}->init(reverseRoute($configline), # server xmits on reverse of its listening route
                                 $self->{mOurStartSeqno},
                                 "d");
    }

    return 1; # Success
}

sub getKey {
   my __PACKAGE__ $self = shift || die;
   die unless
       defined $self->{mIsClient} && defined $self->{mToCoord};
   return chr($self->{mIsClient}).$self->{mToCoord};
}

sub readUser {
    my __PACKAGE__ $self = shift || die;
    my $fh = $self->{mUserHandle} || die;

    unless (defined($self->{mRoute})) {
        # First line config time
        my $ret = sysreadlineNonblocking($fh,\$self->{mLineBuffer});
        if (!defined($ret) || $ret < 0) {  # error or eof
            return $self->{mSRManager}->closeLocal($fh,"Error during config $!");
        }
        return if $ret == 0;

        # Got a full line
        my $data = $self->{mLineBuffer};
        $self->{mLineBuffer} = "";
        chomp $data;
        return $self->configureRoute($data);
    }

    my $ret = $self->{mXmitData}->acceptFromFH($fh,$self);
    if (!defined($ret)) {
        return $self->{mSRManager}->closeLocal($fh,"Error $!");
    }
    
    return 1 if $ret >= 0; # blocked or ok => ok
    # ret < 0;

    if ($self->{mXmitData}->canDeliver() == 0) {
        return 0; # all done
    }
    return 1; # still draining
}

sub handleQuit {
    my __PACKAGE__ $self = shift || die;
    if ($self->isClosedNetwork()) {
        DPSTD("Ignoring Q on closed network");
        return;
    }
    
    unless ($self->{mRecvData}->{mEOFSeen}) {
        $self->{mRecvData}->markEOF() ;
        DPSTD("Marking EOF on mRecv");
    }

    # unless ($self->{mXmitData}->{mEOFSeen}) {
    #     $self->{mXmitData}->markEOF() ;
    #     DPSTD("Marking EOF on mXmit");
    # }
}

sub handleResponse {
    my __PACKAGE__ $self = shift || die;
    my PacketSR_R $rpkt = shift || die;
    my $result = $rpkt->{mResult};
    if ($result == SR_RESULT_OK) {
        die unless $self->{mIsClient};
        my $theirseq = $rpkt->{mSourceSeqno};
        if ($self->{mTheirStartSeqno} >= 0) {
            return DPSTD("Dropping duplicate response $theirseq")
                if $self->{mTheirStartSeqno} == $theirseq;
            die "Inconsistent response $result ".$rpkt->summarize();
        }
        die if defined $self->{mRecvData};
        $self->{mTheirStartSeqno} = $theirseq;
        $self->{mRecvData} = DataQueue->new($self->{mCDM});
        $self->{mRecvData}->init($rpkt->{mRoute},$self->{mTheirStartSeqno},"D");

        # Send first data packet, empty if need be
        my $ret = $self->{mXmitData}->maybeShipData($self->{mRecvData},1);
        die unless $ret; # must have said something

        DPSTD("CLIENT GOING TRANSPARENT $self->{mOurStartSeqno}/$self->{mTheirStartSeqno}");
        return;
    }
    die "WEIRIONSKDV* $rpkt";
}

sub getDesc {
    my __PACKAGE__ $self = shift || die;
    my $ret = "";
    $ret .= "#".fileno($self->{mUserHandle}) if defined($self->{mUserHandle});
    if (defined $self->{mToCoord}) {
        my ($x,$y) = unpackCoord($self->{mToCoord});
        $ret .= "($self->{mIsClient},$x,$y)";
    }
    $ret .= " osn($self->{mOurStartSeqno})";
    $ret .= " tsn($self->{mTheirStartSeqno})";
    return $ret;
}

# Try to accept data to mRecvData (starting at mThisDataSeqno) and
# retire data from mXmitData (starting at mAckRecvSeqno). 
sub maybeReceiveData {
    my __PACKAGE__ $self = shift || die;
    my PacketSR_Dd $ddpkt = shift || die;

    my $rd = $self->{mRecvData} || die;  # Don't be getting here
    my $xd = $self->{mXmitData} || die;  # if you're not ready to rock

    # Return unless we can accept this packet
    my $ravail = $rd->canAppend(); # How much more fits
    my $rendseq = $rd->endSeqno(); # Which byte we need next

    if ($ddpkt->{mThisDataSeqno} == $rendseq) {         # Just what we expected
        my $len = $rd->appendString($ddpkt->{mData});
        die unless $len == length($ddpkt->{mData});       # Window vs buffer size says shouldn't be possible
        DPSTD($self->getDesc()." Accepting $len bytes at $rendseq");
        $self->{mNeedToAck} = 1;
    } elsif ($ddpkt->{mThisDataSeqno} < $rendseq) {      # Already have (some?) of that
        return DPSTD($self->getDesc()." Dropping packet; have $ddpkt->{mThisDataSeqno} got $rendseq");
    } else {
        # Lost packet.  Recover
        die "LOST? GOT $ddpkt->{mThisDataSeqno} BUT EXPECTING $rendseq";
    }

    # Retire what it acks
    $xd->retireToSeqno($ddpkt->{mAckRecvSeqno});
}

sub serverUpdate {
    my __PACKAGE__ $self = shift || die;
#    DPSTD(${\FUNCNAME});
    return 0; # No reason to stop as far as I know
}

sub sendConnect {
    my __PACKAGE__ $self = shift || die;
    DPSTD($self->getDesc()." Connecting to $self->{mRoute}, attempt $self->{mRetryCount}")
        if $self->{mRetryCount}++ > 0;
    my $srcpkt = PacketSR_C::makeFromSREndpoint($self);
    $srcpkt->handleInbound($self->{mCDM});  # Inject into source routing network
    $self->{mLastActivity} = now();
}

sub acceptConnection {
    my __PACKAGE__ $self = shift || die;
    my $from = shift || die;
    my $theirstartseqno = shift; defined $theirstartseqno || die;
    if ($self->{mTheirStartSeqno} >= 0) {
        if ($theirstartseqno == $self->{mTheirStartSeqno}) {
            return DPSTD($self->getDesc()." Ignoring duplicate connection $theirstartseqno");
        }
        die "INCONSISTO ($theirstartseqno vs $self->{mTheirStartSeqno})";
    }
    DPSTD($self->getDesc()." Accept from $from, start seqno $theirstartseqno");
    $self->{mTheirStartSeqno} = $theirstartseqno;
    
    my $rpkt = PacketSR_R->new();
    $rpkt->init(SR_RESULT_OK,$self->{mOurStartSeqno});
    $self->{mSRManager}->sendSR($rpkt,reverseRoute($from));
}

sub sendQuit {
    my __PACKAGE__ $self = shift || die;
    my $qpkt = PacketSR_Qq::makeFromSREndpoint($self);
    $qpkt->handleInbound($self->{mCDM});  # Inject into source routing network
    $self->{mLastActivity} = now();
}

sub clientUpdate {
    my __PACKAGE__ $self = shift || die;
    if ($self->{mTheirStartSeqno} < 0) {        # No response yet
        if ($self->{mLastActivity} < 0 ||
            aged($self->{mLastActivity},10)) {  # Has it been 10 secs since trying?
            if ($self->{mRetryCount} < 100) {
                $self->sendConnect();
            } else {
                die "CLOSE ME HOW";
            }
        }
        return 1; # Stop update; still waiting
    }
}

sub tryToDeliverDataLocally {
    my __PACKAGE__ $self = shift || die;
    my $rd = $self->{mRecvData};
    return unless defined $rd; # Not yet connected

    my $available = $rd->canDeliver();
    return unless $available > 0;

    my $fh = $self->{mUserHandle};
    my $ret = $rd->deliverToFH($fh);
    die "local write failed: $!" unless defined $ret;
    if ($ret < 0) {  # all data delivered
        $self->{mSRManager}->closeLocal($fh);
    }
}

sub tryToShipData {
    my __PACKAGE__ $self = shift || die;
    my $rd = $self->{mRecvData};
    return unless defined $rd; # Not yet connected

    my $xd = $self->{mXmitData};
    die unless defined $xd; # when does server side setup xmit? (when configured)

    if (defined($xd->maybeShipData($rd,$self->{mNeedToAck}))) {
        $self->{mNeedToAck} = 0; # We acked somehow
    }
}


sub update {
    my __PACKAGE__ $self = shift || die;
    my $route = $self->{mRoute};
    return unless defined $route; # Wait indefinitely until config
    if ($self->isFullyClosed()) {
        DPSTD("FULLY CLOSED EXIT");
        exit;
    }
    return if atEndOfRoute($route) && $self->serverUpdate();
    return if atStartOfRoute($route) && $self->clientUpdate();
    $self->tryToShipData();
    $self->tryToDeliverDataLocally();
}

sub onTimeout {
    my ($self) = @_;
    DPPushPrefix($self->getTag()."/".$self->getDesc());
    $self->update();
    DPPopPrefix(); 
}

1;
