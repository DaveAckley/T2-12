## Module stuff
package PacketSR_D; # Source route client<->server data packet
use strict;
use base 'PacketSR';
use fields (
    "mFlags",                   # See D_PKT_FLAG_* in Constants.pm
    "mAckRecvSeqno",            # Highest received seqno (or retry point)
    "mThisDataSeqno",           # Seqno of this packet data if any
    "mData",                    # Packet data
    );

## Imports
use Constants qw(:all);
use DP qw(:all);
use T2Utils qw(:all);

use Exporter qw(import);

our @EXPORT_OK = qw();
our %EXPORT_TAGS;

BEGIN { push @Packable::PACKABLE_CLASSES, __PACKAGE__ }

## Methods
sub new {
    my ($class) = @_;
    my $self = fields::new($class);
    $self->SUPER::new();
    $self->{mCmd} = "D";
    $self->{mFlags} = 0;            # Default value
    $self->{mAckRecvSeqno} = -1;    # Illegal value
    $self->{mThisDataSeqno} = -1;   # Illegal value
    $self->{mData} = undef;         # Illegal value

    return $self;
}

### CLASS METHOD
sub recognize {
    my ($class,$packet) = @_;
    return $class->SUPER::recognize($packet)
        && $packet =~ /^.[^\x00]*\x00D/;  # Urgh
}

##VIRTUAL
sub packFormatAndVars {
    my ($self) = @_;
    my ($parentfmt,@parentvars) = $self->SUPER::packFormatAndVars();
    my ($myfmt,@myvars) =
        ("C N N C/a*", 
         \$self->{mFlags},
         \$self->{mAckRecvSeqno},
         \$self->{mThisDataSeqno},
         \$self->{mData},
        );

    return ($parentfmt.$myfmt,
            @parentvars, @myvars);
}

##VIRTUAL
sub validate {
    my ($self) = @_;
    my $ret = $self->SUPER::validate();
    return $ret if defined $ret;
    return "Bad SR D command '$self->{mCmd}'"
        unless $self->{mCmd} eq "D";
    return "Bad ack seqno"
        unless $self->{mAckRecvSeqno} >= 0;
    return "Bad data seqno"
        unless $self->{mThisDataSeqno} >= 0;
    return "Bad data"
        unless defined($self->{mData});
    return undef;
}

##VIRTUAL
sub deliverLocally {
    my __PACKAGE__ $self = shift || die;
    my EPManager $srm = shift || die;
    my $toserver = ($self->{mFlags} & D_PKT_FLAG_TO_SERVER)!=0;
    my $from = $self->{mRoute};
    atEndOfRoute($from) or
        return DPSTD("Not at end, dropped ".$self->summarize());
    my $ep;
    if ($toserver && defined($ep =  $srm->getServerIfAny($from))) {
        unless (defined($ep->{mFromNetBuffer})) {
            $ep->{mFromNetBuffer} = "";
            die "WRTDKL?" unless defined $ep->{mFromNetAckedSeq};
            DPSTD("SERVER GOING TRANSPARENT $ep->{mToNetFrontSeq}/$ep->{mFromNetAckedSeq}");
        }
        #DPSTD("got server ssre ($ep) from ($from)");
    } else {
        $ep =  $srm->getClientIfAny($from);
        DPSTD("No client found for route $from, dropping ".$self->summarize()) unless defined $ep;
    }

    if (defined($ep)) {
        DPPKT($ep->getDesc()." D/L D:$from [".formatDFlags($self->{mFlags})."] dlen"
          .length($self->{mData})
          ." $self->{mThisDataSeqno}/$self->{mAckRecvSeqno}");
        $ep->maybeReceiveData($self);
    }
}


1;

