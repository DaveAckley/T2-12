## Module stuff
package EP;
use strict;
use strict 'refs';
use base 'TimeoutAble';
use fields (
    "mRoute",           # server or client route
    "mFlags",           # urgh room for fiddly bits of state
    "mEPKey",           # relative coordinate client/server key
    "mLocalCxn",        # handle returned by socket->accept()
    "mLocalEOF",        # >0 if eof has been seen on mLocalCxn
    "mEPManager",       # who to notify about lifecycle changes
    "mLineBuffer",      # Buffer to accumulate first-line route info
    "mPktFromNet",      # Latest packet from net or undef
    "mToNetFrontSeq",   # Current min outbound seqno, set in tryConfigure success
    "mToNetNextSeq",    # Min unsent outbound seqno, set in tryContact success 
    "mToNetLastSeq",    # Max outbound seqno ever, set on mLocalEOF after tryConfigure success
    "mToNetFirstSeq",   # Original outbound seqno for computing total traffic
    "mToNetBuffer",     # Unacked outbound data 
    "mFromNetAckedSeq", # Seqno of end of mFromNetBuffer or undef before connect
    "mFromNetLastSeq",  # Max inbound seqno ever
    "mFromNetFirstSeq", # Original inbound seqno
    "mFromNetBuffer",   # Undelivered inbound data
    "mNetConnectTime",  # When connection was first established
    "mNeedToAck",       # Data from net needs to be acked even if we have nothing to send
    "mLastActivity",    # time() of last timeout-able activity
    );

use Exporter qw(import);

our @EXPORT_OK = qw();
our %EXPORT_TAGS;

## Imports

use T2Utils qw(:all);
use MFZUtils qw(:all);
use DP qw(:all);
#use TimeQueue;
use Constants qw(:all);
use PacketSR_C;
use PacketSR_D;
use PacketSR_Q;

## Methods
sub new {
    my ($class,$cdm) = @_;
    my __PACKAGE__ $self = fields::new($class);
    $self->SUPER::new("EP",$cdm);
    $self->{mRoute} = undef;         # Illegal value: Server or client route
    $self->{mFlags} = 0;             # Default value
    $self->{mEPKey} = undef;         # Illegal value: Endpoint key with isclient + (dx,dy)
    $self->{mLocalCxn} = undef;      # Illegal value: socket handle from accept
    $self->{mLocalEOF} = undef;      # Illegal value: true if eof has been seen
    $self->{mEPManager} = undef;     # Illegal value
    $self->{mLineBuffer} = undef;    # Illegal value: String accumulating first line
    $self->{mPktFromNet} = undef;    # Just-received inbound net packet, if any
    $self->{mToNetFrontSeq} = undef; # Illegal value: Outbound net front of buffer seqno
    $self->{mToNetNextSeq} = undef;  # Illegal value: Outbound net next unsent seqno
    $self->{mToNetLastSeq} = undef;  # Illegal value: Outbound side last seqno to send
    $self->{mToNetFirstSeq} = undef; # Illegal value: Outbound side starting seqno
    $self->{mToNetBuffer} = undef;   # Illegal value: Outbound unacked data string
    $self->{mFromNetAckedSeq} = undef; # Illegal value: Inbound end of mFromNetBuffer seqno
    $self->{mFromNetLastSeq} = undef; # Illegal value: Inbound end of mFromNetBuffer seqno
    $self->{mFromNetFirstSeq} = undef; # Illegal value: Inbound side starting seqno
    $self->{mFromNetBuffer} = undef; # Illegal value: Inbound data waiting for local delivery
    $self->{mNetConnectTime} = undef; # Illegal value: now() as of setting mFromNetAckedSeq
    $self->{mNeedToAck} = undef;     # Illegal value: Bool if we need to ack even w/no OB data
    $self->{mLastActivity} = undef;  # Illegal value: Last time of trying the appropriate thing
    
    $self->{mCDM}->getTQ()->schedule($self);
    $self->defaultInterval(-.2);

    return $self;
}

sub init {
    my __PACKAGE__ $self = shift || die;
    my ($socket,$epmgr) = @_;
    defined $socket or die;
    defined $epmgr or die;

    $self->{mLocalCxn} = $socket;
    $self->{mLocalEOF} = 0;
    $self->{mEPManager} = $epmgr;
    $self->{mLineBuffer} = "";  
}

sub final {
    my __PACKAGE__ $self = shift || die;
    my $epm = $self->{mEPManager};
    die unless defined $epm;
    $self->{mEPManager} = undef;
    $self->{mCDM}->getTQ()->unschedule($self);

    DPSTD("Running final hook for ".$self->getTag());
    $epm->dropEP($self);
}

sub getKey {
    my __PACKAGE__ $self = shift || die;
    return $self->{mEPKey};
}

sub doDIE {
    my __PACKAGE__ $self = shift || die;
    my $msg = shift;
    DPSTD($msg) if defined $msg;
    $self->setFlags(EP_FLAG_LOCAL_ABORT);
}

sub tryReadLocal {
    my __PACKAGE__ $self = shift || die;
    die "IMPLEMENT ME";
}

sub isClient {
    my __PACKAGE__ $self = shift || die;
    return defined($self->{mRoute}) && atStartOfRoute($self->{mRoute});
}

sub isServer {
    my __PACKAGE__ $self = shift || die;
    return defined($self->{mRoute}) && atEndOfRoute($self->{mRoute});
}

use constant MAX_DATA_BUFFER_LENGTH => 1<<13;
use constant MAX_DATA_BYTES_IN_FLIGHT => 1<<11;

sub state_NEED_ABORT {
    my __PACKAGE__ $self = shift || die;
    return ($self->{mFlags} & (EP_FLAG_LOCAL_ABORT | EP_FLAG_REMOTE_ABORT)) != 0;
}

sub state_NEED_CONFIGURE {
    my __PACKAGE__ $self = shift || die;
    return !defined($self->{mRoute});
}

sub state_NEED_CONTACT {
    my __PACKAGE__ $self = shift || die;
    return
        defined($self->{mRoute}) &&
        !defined($self->{mFromNetAckedSeq});
}

sub state_NEED_IO {
    my __PACKAGE__ $self = shift || die;
    return                                       # We need IO, if:
        !defined($self->{mToNetLastSeq}) ||      # we don't know last local seqno or
        !defined($self->{mFromNetLastSeq}) ||    # we don't know last remote seqno or
        length($self->{mToNetBuffer}) > 0 ||     # we have outbound data unsent or
        length($self->{mFromNetBuffer}) > 0 ||   # we have inbound data undelivered or
        $self->{mNeedToAck};                     # everything's set but we need to ack
}

sub handleQuit {
    my __PACKAGE__ $self = shift || die;
    my PacketSR_Q $pkt = shift || die;
    DPSTD($self->getDesc()." Quit $pkt->{mStatus} received");
    $self->setFlags(EP_FLAG_REMOTE_ABORT);
}

sub tryAbort {
    my __PACKAGE__ $self = shift || die;
    my $die = 0;
    if ($self->ifFlags(EP_FLAG_LOCAL_ABORT)) {
        # Try to signal peer
        if (defined($self->{mRoute}) && defined($self->{mFromNetAckedSeq})) {
            my $epm = $self->{mCDM}->{mEPManager} || die;
            my $route = $self->{mRoute};
            $route = reverseRoute($route) if $self->isServer();
            my $qpkt = PacketSR_Q->new();
            $qpkt->{mFlags} |= Q_PKT_FLAG_TO_SERVER if $self->isClient();
            $qpkt->{mStatus} = 255; # XXXX We don't know why we're doing this
            DPSTD("To ($route): ".$qpkt->summarize());
            $epm->sendSR($qpkt,$route);
        }
        ++$die;
    }
    if ($self->ifFlags(EP_FLAG_REMOTE_ABORT)) {
        ++$die;
    }
    $self->final() if $die > 0;
}

sub tryConfigure {
    my __PACKAGE__ $self = shift || die;
    my $hdl = $self->{mLocalCxn} || die;
    my $ret = sysreadlineNonblocking($hdl, \$self->{mLineBuffer});
    die "Local read: $!" unless defined $ret;

    return $self->doDIE("EOF before route") if $ret < 0;
    return 1 if $ret == 0; # Need more

    # $ret > 0: Have line
    chomp $self->{mLineBuffer};
    my $line = $self->{mLineBuffer};
    my ($pre,$eight,$post) = unpackRoute($line);
    return $self->doDIE("Bad route '$line'") unless defined $post;
    return $self->doDIE("Route too long '$line'") unless length($line) <= 32;

    if ($pre eq "") { # We are a server
        $self->{mRoute} = "$eight$post";
    } elsif ($post eq "") { # We are a client
        $self->{mRoute} = "$pre$eight";
    } else {
        return $self->doDIE("Midroute unsupported");
    }

    $self->{mEPKey} = collapseRouteToEndpointKey($self->{mRoute});
    my $epm = $self->{mEPManager};
    unless ($epm->registerClientServer($self)) {
        $self->{mEPKey} = undef; # Avoid clobbering existing EP during final()
        return $self->doDIE("'$line' blocked by existing connection");
    }

    # Set up other configuration state
    my $fileno = fileno($hdl);
    DPSTD("CONFIGURED '$line' LOCAL $fileno, ".formatEndpointKey($self->{mEPKey}));

    $self->{mToNetBuffer} = "";
    $self->{mToNetFrontSeq} = int(rand(1<<16))|1;
    $self->{mToNetFirstSeq} = $self->{mToNetFrontSeq};
    $self->{mToNetNextSeq} = $self->{mToNetFrontSeq};
    return 1;
}

sub formatTraffic {
    my __PACKAGE__ $self = shift || die;
    my ($out,$outb) = ("--",0);
    my ($in,$inb) = ("--",0);
    my $bps = "";
    if (defined($self->{mToNetFirstSeq})) {
        $outb = $self->{mToNetFrontSeq} - $self->{mToNetFirstSeq};
        $out = formatSize($outb,1)."B";
    }

    if (defined($self->{mFromNetAckedSeq})) {
        $inb = $self->{mFromNetAckedSeq} - $self->{mFromNetFirstSeq};
        $in = formatSize($inb,1)."B"
    }

    if (defined($self->{mNetConnectTime})) {
        my $seconds = now() - $self->{mNetConnectTime};
        if ($seconds > 0) {
            my $rate = ($outb+$inb) / $seconds;
            $bps = "/".formatSize($rate)."Bps";
        }
    }
    return "$in/$out$bps";
}

# Client handles connection response from server here.
sub handleResponse {
    my __PACKAGE__ $self = shift || die;
    my PacketSR_R $rpkt = shift || die;
    my $result = $rpkt->{mResult};
    if ($result == SR_RESULT_OK) {
        die unless $self->isClient();
        my $theirseq = $rpkt->{mSourceSeqno};
        if (defined($self->{mFromNetAckedSeq})) {  # Might be a dupe
            return DPSTD("Dropping duplicate response $theirseq")
                if $self->{mFromNetAckedSeq} == $theirseq;
            die "HANDLE ME: Inconsistent response $result ".$rpkt->summarize();
        }
        $self->{mFromNetAckedSeq} = $theirseq;  # We've now acked nothing, starting from here..
        $self->{mFromNetFirstSeq} = $self->{mFromNetAckedSeq};  # For traffic counting
        $self->{mNetConnectTime} = now();   # Connection is now established

        $self->{mFromNetBuffer} = "";           # Here's where we'll hold stuff pending local delivery

        # Send first data packet, empty if need be
        $self->setNeedToAck();
        my $ret = $self->maybeSendDataToNet(D_PKT_FLAG_FIRST_SEQ);
        die unless $ret; # must have said something

        return DPSTD("CLIENT GOING TRANSPARENT $self->{mToNetFrontSeq}/$self->{mFromNetAckedSeq}");
    }

    if ($result == SR_RESULT_CONNREFUSED) {
        return DPSTD("CONNECTION TO $self->{mRoute} REFUSED, WAITING");
    }
    die "WEIRIONSKDV* $rpkt";
}

sub setNeedToAck {
    my __PACKAGE__ $self = shift || die;
    unless ($self->{mNeedToAck}) {
        $self->reschedule(0.1);
        $self->{mNeedToAck} = 1;
    }
}

sub ifFlags {
    my __PACKAGE__ $self = shift || die;
    my $flags = shift||0;
    return ($self->{mFlags} & $flags) != 0;
}

sub setFlags {
    my __PACKAGE__ $self = shift || die;
    my $flags = shift||0;
    $self->{mFlags} |= $flags;
}

sub clearFlags {
    my __PACKAGE__ $self = shift || die;
    my $flags = shift||0;
    $self->{mFlags} &= ~$flags;
}

sub isInSync {
    my __PACKAGE__ $self = shift || die;
    return $self->ifFlags(EP_FLAG_IN_SYNC);
}

sub setInSync { 
    my __PACKAGE__ $self = shift || die;
    $self->setFlags(EP_FLAG_IN_SYNC);
}

sub clearInSync {
    my __PACKAGE__ $self = shift || die;
    $self->clearFlags(EP_FLAG_IN_SYNC);
}

# return undef if empty or too much pending, and not $evenifempty
# return 1 if packet sent (possibly empty if $evenifempty)
sub maybeSendDataToNet {
    my __PACKAGE__ $self = shift || die;
    my $optflags = shift || 0;

    my $evenifempty = $self->{mNeedToAck} || 0;

    die unless defined $self->{mRoute};
    my $unacked = $self->{mToNetNextSeq} - $self->{mToNetFrontSeq};
    my $available = length($self->{mToNetBuffer}) - $unacked;
    if ($unacked >= MAX_DATA_BYTES_IN_FLIGHT) {
        return undef unless $evenifempty;   ## TOO MUCH ALREADY OUT
        # If we have mNeedToAck on our side, but too much unacked data
        # we've already sent them, I guess the thing to do is pretend
        # there's nothing available and send an empty data packet.
        $available = 0;
    }

    die if $available < 0;  # Inconsistent?
    return undef unless (($available > 0) || $evenifempty);  ## NOTHING TO SAY

    my $shipamt = min($available, MAX_D_TYPE_DATA_LENGTH);
    my $data = substr($self->{mToNetBuffer},$unacked,$shipamt);
    my $pkt = PacketSR_D->new();

    $pkt->{mFlags} = $optflags;
    $pkt->{mFlags} |= D_PKT_FLAG_TO_SERVER if $self->isClient(); 

    $pkt->{mAckRecvSeqno} = $self->{mFromNetAckedSeq};
    $pkt->{mThisDataSeqno} = $self->{mToNetNextSeq};

    $pkt->{mData} = $data;
    $self->{mToNetNextSeq} += $shipamt;

    # Check for end AFTER considering the data in the packet
    if (defined($self->{mToNetLastSeq}) && $self->{mToNetLastSeq} == $self->{mToNetNextSeq}) {
        $pkt->{mFlags} |= D_PKT_FLAG_LAST_SEQ;
        #DPSTD("SETTING LAST: ".formatDFlags($pkt->{mFlags}));
    }

    DPPKT("Sending $pkt->{mCmd}:$self->{mRoute} ["
          .formatDFlags($pkt->{mFlags})
          ."] $pkt->{mThisDataSeqno}/$pkt->{mAckRecvSeqno} next $self->{mToNetNextSeq} datalen "
          .length($pkt->{mData}));
    my $epm = $self->{mCDM}->{mEPManager} || die;
    my $route = $self->{mRoute};
    $route = reverseRoute($route) if $self->isServer();
    $epm->sendSR($pkt,$route);
    $self->{mNeedToAck} = 0;
    $self->{mLastActivity} = now();
    return 1;
}

sub maybeReceiveData {
    my __PACKAGE__ $self = shift || die;
    my PacketSR_D $pkt = shift || die;

    if (!defined($self->{mRoute}) ||
        !defined($self->{mFromNetAckedSeq})) {
        die "XXX DON'T BE HERE";
    }

    my $inboundlen = length($self->{mFromNetBuffer});      # inbound we're holding
    my $ravail = MAX_DATA_BUFFER_LENGTH - $inboundlen;     # how much more we can take

    # Pick up eos if marked
    if ($pkt->{mFlags} & D_PKT_FLAG_LAST_SEQ) {
        if (!defined($self->{mFromNetLastSeq}) || $self->{mFromNetLastSeq} != $pkt->{mThisDataSeqno}) {
            DPSTD("INCONSISTENT LASTSEQ, have $self->{mFromNetLastSeq}, got $pkt->{mThisDataSeqno}")
                if defined ($self->{mFromNetLastSeq});
            $self->{mFromNetLastSeq} = $pkt->{mThisDataSeqno};
            $self->setNeedToAck();
            DPPKT("NETLAST RECVD: $self->{mFromNetLastSeq}");
        }
    }

    # Pick up retry if marked
    if ($pkt->{mFlags} & D_PKT_FLAG_RETRY_SEQ) {
        if ($self->{mToNetNextSeq} > $pkt->{mAckRecvSeqno}) {
            DPSTD("RETRY REQUEST: $self->{mToNetNextSeq} (was) < $pkt->{mAckRecvSeqno} (now)");
            $self->{mToNetNextSeq} = $pkt->{mAckRecvSeqno};
        }
    }

    # Supplied data is just what we're expecting.  Take as much as fits.
    if ($pkt->{mThisDataSeqno} == $self->{mFromNetAckedSeq}) {
        my $data = $pkt->{mData};
        my $take = min(length($data),$ravail);  # min of all they bring or the room we've got
        $self->{mFromNetBuffer} .= substr($data,0,$take);
        $self->{mFromNetAckedSeq} += $take;
        $self->setNeedToAck() if $take > 0;          # Need to ack if we moved the needle
        $self->setInSync();
    } elsif ($pkt->{mThisDataSeqno} < $self->{mFromNetAckedSeq}) {
        if ($self->isInSync()) {
            DPSTD($self->getDesc()." DROPPING DUP PACKET $pkt->{mThisDataSeqno} (pkt) < $self->{mFromNetAckedSeq} (us)");
        }
        return;
    } else {
        # Lost packet.  For now, just try to signal restart from what we were expecting
        if ($self->isInSync()) {    # Only send retry on first sign we're blown
            $self->setNeedToAck();
            DPSTD($self->getDesc()." LOST PACKET $pkt->{mThisDataSeqno} (pkt) != $self->{mFromNetAckedSeq} (us)");
            $self->maybeSendDataToNet(D_PKT_FLAG_RETRY_SEQ);  
            $self->clearInSync();
        }
        return;
    }

    # Also, retire any outbound stuff $pkt acks
    my $retiretoseq = $pkt->{mAckRecvSeqno};
    my $count = $retiretoseq - $self->{mToNetFrontSeq};
    die unless $count >= 0;
    if ($count > 0) {
        substr($self->{mToNetBuffer},0,$count) = "";
        $self->{mToNetFrontSeq} = $retiretoseq;
        DPSTD("Retiring $count to $retiretoseq on dq route $self->{mRoute}");
    }
}

# Here for server EP to accept connection from client
# (See handleResponse for where client EP handles response generated here)
sub acceptConnection {
    my __PACKAGE__ $self = shift || die;
    my $fromroute = shift||die;
    my $theirseq = shift||die;

    if (defined($self->{mFromNetAckedSeq})) {
        return DPSTD($self->getDesc()." Ignoring duplicate connection $theirseq")
            if $theirseq == $self->{mFromNetAckedSeq};
        die "INCONSISTO ($theirseq vs $self->{mFromNetAckedSeq})";
    }
    
    DPSTD($self->getDesc()." Accept from $fromroute, their start seqno $theirseq");
    $self->{mFromNetAckedSeq} = $theirseq;
    $self->{mFromNetFirstSeq} = $self->{mFromNetAckedSeq};
    $self->{mNetConnectTime} = now();   # Connection is now established (server side)
    
    my $rpkt = PacketSR_R->new();
    $rpkt->init(SR_RESULT_OK,$self->{mToNetFrontSeq});
    $self->{mEPManager}->sendSR($rpkt,reverseRoute($fromroute));
}

# Return -1 if eof seen
# Return 0 if no input or input/eof unassessed since too much already read
# Return 1 if additional input found
# Return undef and set $! on error
sub checkInput {
    my __PACKAGE__ $self = shift || die;
    return -1 if $self->{mLocalEOF};

    my $max = MAX_DATA_BUFFER_LENGTH - length($self->{mToNetBuffer});
    return 0 if $max <= 0;

    my $data;
    my $ret = sysread($self->{mLocalCxn}, $data, $max);
    if (!defined($ret)) {
        unless ($!{EAGAIN}) {
            return undef;
        }
        return 0;
    }
    if ($ret == 0) {
        $self->{mLocalEOF} = 1;
        return -1;
    }
    $self->{mToNetBuffer} .= $data;
    return 1;
}

sub tryContact {
    my __PACKAGE__ $self = shift || die;

    # Check for relevant net activity
    if (defined($self->{mPktFromNet})) {
        die "XXXX GOT PKT";
    }

    # Check for local eof
    if ($self->checkInput() < 0) {
        if ($self->isClient()) {
            return $self->doDIE("Contact abandoned") if length($self->{mToNetBuffer}) > 0;
            return $self->doDIE();
        }
    }

    # Check for timeout/retry to connect
    return 1 unless $self->isClient();  # Only clients reach out

    my $last = $self->{mLastActivity};
    return 1 if defined($last) && !aged($last, 8); # Wait more
    $self->{mLastActivity} = now();

    my $sfpkt = PacketSR_C->new();
    $sfpkt->{mSourceSeqno} = $self->{mToNetFrontSeq} || die;

    print "TRY CONTACT ".$self->{mRoute}."\n";
    die unless $self->isClient();
    my $epm = $self->{mCDM}->{mEPManager};
    $epm->sendSR($sfpkt,$self->{mRoute});
}

sub tryIO {
    my __PACKAGE__ $self = shift || die;

    while (1) {

        ## Try to pick up more data from the local user
        if (!defined($self->{mToNetLastSeq})) {    # defined if we've already seen local eof
            my $ret = $self->checkInput();         # Take some input 
            return $self->doDIE("Read failed: $!") unless defined $ret;

            if ($ret < 0) {   # Saw local EOF, set outbound last seq
                $self->{mToNetLastSeq} = $self->{mToNetFrontSeq} + length($self->{mToNetBuffer});
                $self->setNeedToAck(); 
                DPSTD("SETTING OB LASTSEQ=$self->{mToNetLastSeq}");
            } 
        }

        ## And try to flush to the local user
        my $fromlen = length($self->{mFromNetBuffer});
        if ($fromlen >= 0) { ## XXX TRY ALLOWING 0 LEN WRITES
            my $count = syswrite $self->{mLocalCxn}, $self->{mFromNetBuffer}, $fromlen;
            if (!defined($count)) {
                return $self->doDIE("Write failed: $!") unless $!{EAGAIN};
                $count = 0;
            }
            substr($self->{mFromNetBuffer},0,$count) = "";  # Munch off what we reported
        }

        ## Try to ship data to the net
        last unless $self->maybeSendDataToNet(0);
    }

    return 1;
}

sub getDesc {
    my __PACKAGE__ $self = shift || die;
    my $ret = $self->getTag();
    $ret .= "+".fileno($self->{mLocalCxn}) if defined($self->{mLocalCxn}) && defined(fileno($self->{mLocalCxn})); 
    $ret .= '@'.formatEndpointKey($self->{mEPKey}) if defined $self->{mEPKey};
#    $ret .= " osn($self->{mOurStartSeqno})";
#    $ret .= " tsn($self->{mTheirStartSeqno})";
    return $ret;
}

sub advance {
    my __PACKAGE__ $self = shift || die;
    return $self->tryAbort()     if $self->state_NEED_ABORT();
    return $self->tryConfigure() if $self->state_NEED_CONFIGURE();
    return $self->tryContact()   if $self->state_NEED_CONTACT();
    return $self->tryIO()        if $self->state_NEED_IO();

    DPSTD("MISSION ACCOMPLISHED ".$self->formatTraffic());
    $self->final();
}

my $inupdate = 0;
sub update {
    my __PACKAGE__ $self = shift || die;
    die "Recursive update" if $inupdate;
    $inupdate = 1;
    my $ret = $self->advance();
    $inupdate = 0;
    return $ret;
}

sub onTimeout {
    my ($self) = @_;
    DPPushPrefix($self->getDesc());
    $self->update();
    DPPopPrefix(); 
}

1;
