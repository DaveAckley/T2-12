## Module stuff
package PacketSR_Dd; # Source route client->server (D) or server->client (d) data packet
use strict;
use base 'PacketSR';
use fields qw(
    mAckRecvSeqno
    mThisDataSeqno
    mData
    );

## Imports
use Constants qw(:all);
use DP qw(:all);
use T2Utils qw(:all);

use SREndpoint;

use Exporter qw(import);

our @EXPORT_OK = qw();
our %EXPORT_TAGS;

BEGIN { push @Packable::PACKABLE_CLASSES, __PACKAGE__ }

## Methods
sub new {
    my ($class) = @_;
    my $self = fields::new($class);
    $self->SUPER::new();
    $self->{mCmd} = undef;          # Illegal value
    $self->{mAckRecvSeqno} = -1;    # Illegal value
    $self->{mThisDataSeqno} = -1;   # Illegal value
    $self->{mData} = undef;         # Illegal value

    return $self;
}

### CLASS METHOD
sub recognize {
    my ($class,$packet) = @_;
    return $class->SUPER::recognize($packet)
        && $packet =~ /^.[^\x00]*\x00[Dd]/;  # Urgh
}

##VIRTUAL
sub packFormatAndVars {
    my ($self) = @_;
    my ($parentfmt,@parentvars) = $self->SUPER::packFormatAndVars();
    my ($myfmt,@myvars) =
        ("N N C/a*", 
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
    return "Bad SR Dd command '$self->{mCmd}'"
        unless $self->{mCmd} eq "D" || $self->{mCmd} eq "d";
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
    my SRManager $srm = shift || die;
    my $toserver = ($self->{mCmd} eq "D"); 
    my $from = $self->{mRoute};
    DPSTD("handling Dd: toserver($toserver) from($from)");

    atEndOfRoute($from) or
        return DPSTD("Not at end, dropped ".$self->summarize());
    my $ssre;
    if ($toserver && defined($ssre =  $srm->getServerIfAny($from))) {
        unless (defined($ssre->{mRecvData})) {
            $ssre->{mRecvData} = DataQueue->new($ssre->{mCDM});
            $ssre->{mRecvData}->init($from,$ssre->{mTheirStartSeqno},"d");
            DPSTD("SERVER GOING TRANSPARENT $ssre->{mOurStartSeqno}/$ssre->{mTheirStartSeqno}");
        }
        DPSTD("got server ssre ($ssre) from ($from)");
    } else {
        $ssre =  $srm->getClientIfAny($from);
        DPSTD("undefined client ssre from ($from) :") unless defined $ssre;
    }


    $ssre->maybeReceiveData($self)
        if defined $ssre;
}


1;

