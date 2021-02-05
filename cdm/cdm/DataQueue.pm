## Module stuff
package DataQueue;
use strict;
use strict 'refs';
use base 'TimeoutAble';
use fields qw(
    mRoute
    mFrontSeqno
    mNextSeqno
    mLastSeqno
    mBuffer
    mDataCmd
    );

use Exporter qw(import);

our @EXPORT_OK = qw();
our %EXPORT_TAGS;

## Imports

use T2Utils qw(:all);
use MFZUtils qw(:all);
use DP qw(:all);
use TimeQueue;
use Constants qw(:all);
use PacketSR_Qq;
use PacketSR_Dd;
use SREndpoint;

## Methods
sub new {
    my ($class,$cdm) = @_;
    defined $cdm or die;
    my __PACKAGE__ $self = fields::new($class);
    $self->SUPER::new("DataQueue",$cdm);
    $self->{mRoute} = undef;      # Illegal value
    $self->{mFrontSeqno} = -1;      # Illegal value
    $self->{mNextSeqno} = -1;       # Illegal value
    $self->{mLastSeqno} = undef;    # Illegal value
    $self->{mBuffer} = undef;       # Illegal value
    $self->{mDataCmd} = undef;      # Illegal value

    $self->{mCDM}->getTQ()->schedule($self);
    $self->defaultInterval(-2);
    return $self;
}

sub init {
    my __PACKAGE__ $self = shift || die;
    my ($toroute,$startseqno,$datacmd) = @_;
    defined $toroute or die;
    defined($startseqno) && $startseqno >= 0 or die;
    defined($datacmd) or die;
    my $cdm = $self->{mCDM};

    die "REINIT?" if defined $self->{mRoute};
    $self->{mRoute} = $toroute;
    $self->{mFrontSeqno} = $startseqno;
    $self->{mNextSeqno} = $startseqno;
    $self->{mLastSeqno} = -1;  # Once >= 0, mBuffer can only shrink
    $self->{mBuffer} = "";
    $self->{mDataCmd} = $datacmd; # "D" (c->s) or "d" (s->c)
    DPSTD("INIT DQ ($toroute,$startseqno,$datacmd)");
}

use constant MAX_DATA_BUFFER_LENGTH => 1<<12;
use constant MAX_DATA_BYTES_IN_FLIGHT => 1<<9;

sub canAppend {
    my __PACKAGE__ $self = shift || die;
    die unless defined $self->{mRoute};
    return 0 if $self->{mLastSeqno} >= 0;
    return MAX_DATA_BUFFER_LENGTH - length($self->{mBuffer});
}

sub canDeliver {
    my __PACKAGE__ $self = shift || die;
    die unless defined $self->{mRoute};
    return length($self->{mBuffer});
}

sub endSeqno {
    my __PACKAGE__ $self = shift || die;
    return $self->{mFrontSeqno} + length($self->{mBuffer});
}

# return # of bytes of string appended, 0..length(string)
sub appendString {
    my __PACKAGE__ $self = shift || die;
    my $data = shift; defined $data || die;
    die unless defined $self->{mRoute};
    my $cantake = $self->canAppend();
    my $take = min(length($data),$cantake);
    $self->{mBuffer} .= substr($data,0,$take);
    $self->{mNextSeqno} += $take; # ?? But we don't know if $data is properly aligned?
    return $take;
}

sub deliveryDone {
    my __PACKAGE__ $self = shift || die;
    return $self->{mFrontSeqno} == $self->{mLastSeqno} && $self->canDeliver() == 0;
}

# return 0 if would block
# return undef and set $! if error
# return 1 eof not seen (and data may or may not be buffered)
# return -1 if eof seen (but data may still be buffered)
sub acceptFromFH {
    my __PACKAGE__ $self = shift || die;
    my $fh = shift || die;
    my SREndpoint $sre = shift || die;

    return -1 if $self->{mLastSeqno} >= 0;

    my $acceptable = $self->canAppend();
    return 1 if $acceptable == 0; # No room now but attempts should continue

    my $data;
    my $count = sysread $fh, $data, $acceptable;
    if (!defined($count)) {
        return 0 if $!{EAGAIN};
        return undef; # $! set by sysread
    }
    if ($count == 0) {
        die if $self->{mLastSeqno} >= 0;
        $self->{mLastSeqno} = $self->endSeqno();
        
        die "REIMPLEMENT ME";
#        return $self->{mCDM}->{mSRManager}->closeLocal($fh,undef);
    }

    $self->{mBuffer} .= $data;
    DPSTD("Accepted $count from local, buffer len now ".length($self->{mBuffer}));

    return 1;
}

# return 0 if blocked
# return undef and set $! if error
# return 1 if data deliveries should continue
# return -1 if all data has been delivered
sub deliverToFH {
    my __PACKAGE__ $self = shift || die;
    my $fh = shift || die;
    die unless defined $self->{mRoute};
    return -1 if $self->deliveryDone();

    my $avail = $self->canDeliver();
    return 1 unless $avail > 0;

    my $count = syswrite $fh, $self->{mBuffer}, $avail;
    if (!defined($count)) {
        if ($!{EAGAIN}) {
            return 0;
        }
        return undef; # Error, $! set by syswrite
    }
    # retire the first $count bytes of buffer
    $self->retireToSeqno($count + $self->{mFrontSeqno});

    if ($self->deliveryDone()) {
        unless ($self->isClosedNetwork()) {
            $self->sendQuit();
        }
        die "XXSXREIMPLEMENT ME";
#        $self->{mCDM}->{mSRManager}->closeLocal($fh,undef);
        return -1;
    }
    return 1;
}

sub nextString {
    my __PACKAGE__ $self = shift || die;
    my $max = shift; defined $max or die;
    my $alreadyout = $self->{mNextSeqno} - $self->{mFrontSeqno};
    my $available = length($self->{mBuffer}) - $alreadyout;
    my $windowsize = MAX_DATA_BYTES_IN_FLIGHT;
    my $advance = min($max,$available);
    $self->{mNextSeqno} += $advance;
    return substr($self->{mBuffer},$alreadyout,$advance);
}

sub retireToSeqno {
    my __PACKAGE__ $self = shift || die;
    my $seqno = shift || die;
    die unless $seqno >= $self->{mFrontSeqno};
    my $count = $seqno - $self->{mFrontSeqno};
    substr($self->{mBuffer},0,$count) = "";
    $self->{mFrontSeqno} = $seqno;
    DPSTD("Retiring $count to $seqno on dq route $self->{mRoute}");
    return $count;
}

sub retryFromSeqno {
    my __PACKAGE__ $self = shift || die;
    my $seqno = shift || die;
    die if $seqno < $self->{mFrontSeqno};
    return 0 if $seqno > $self->{mNextSeqno}; # Already reset farther back
    $self->{mNextSeqno} = $seqno;
    return 1;
}    

# sub markEOF {
#     my __PACKAGE__ $self = shift || die;
#     die if $self->{mEOFSeen};
#     return $self->{mEOFSeen} = 1;
# }


sub maybeShipData {
    my __PACKAGE__ $self = shift || die;
    my __PACKAGE__ $rq = shift || die;
    my $emptyokopt = shift || 0; 

    die unless defined $self->{mRoute};
    my $unacked = $self->{mNextSeqno} - $self->{mFrontSeqno};
    return unless $unacked < MAX_DATA_BYTES_IN_FLIGHT;
    my $available = length($self->{mBuffer}) - $unacked;
    return unless ($available > 0) || ($emptyokopt && $available == 0);
    my $shipamt = min($available, MAX_D_TYPE_DATA_LENGTH);
    my $data = substr($self->{mBuffer},$unacked,$shipamt);
    my $pkt = PacketSR_Dd->new();
    $pkt->{mCmd} = $self->{mDataCmd};
    $pkt->{mAckRecvSeqno} = $rq->{mFrontSeqno};
    $pkt->{mThisDataSeqno} = $self->{mNextSeqno};
    $pkt->{mData} = $data;
    $self->{mNextSeqno} += $shipamt;
    DPSTD("SEND $pkt->{mCmd} to $self->{mRoute} ack $pkt->{mAckRecvSeqno} seq $pkt->{mThisDataSeqno} len ".length($pkt->{mData}));
    my $srm = $self->{mCDM}->{mEPManager} || die;
    $srm->sendSR($pkt,$self->{mRoute});
    return 1;
}

sub update {
    my __PACKAGE__ $self = shift || die;
    my $route = $self->{mRoute};
    DPSTD("Update?");
    # No initiative so far..
}

sub onTimeout {
    my ($self) = @_;
    DPPushPrefix($self->getTag());
    $self->update();
    DPPopPrefix(); 
}

1;
