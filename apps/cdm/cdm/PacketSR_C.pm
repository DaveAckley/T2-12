## Module stuff
package PacketSR_C; # Source route client->server connection attempt
use strict;
use base 'PacketSR';
use fields qw(
    mSourceSeqno
    );

## Imports
use Constants qw(:all);
use DP qw(:all);
use T2Utils qw(:all);

use SREndpoint;
use PacketSR_R;

use Exporter qw(import);

our @EXPORT_OK = qw();
our %EXPORT_TAGS;

BEGIN { push @Packable::PACKABLE_CLASSES, __PACKAGE__ }

### CLASS METHOD
sub makeFromSREndpoint {
    my SREndpoint $sre = shift || die;
    my $route = $sre->{mRoute};
    atStartOfRoute($route) or die; 

    my $seqno = $sre->{mOurStartSeqno};
    $seqno >= 0 or die;

    my $sfpkt = PacketSR_C->new();
    $sfpkt->{mRoute} = $route;
    $sfpkt->{mSourceSeqno} = $seqno;
    return $sfpkt;
}

## Methods
sub new {
    my ($class) = @_;
    my $self = fields::new($class);
    $self->SUPER::new();
    $self->{mCmd} = "C";            # We are an SR C packet
    $self->{mSourceSeqno} = -1;     # Illegal value

    return $self;
}

### CLASS METHOD
sub recognize {
    my ($class,$packet) = @_;
    return $class->SUPER::recognize($packet)
        && $packet =~ /^.[^\x00]*\x00C/;  # Urgh
}

##VIRTUAL
sub packFormatAndVars {
    my ($self) = @_;
    my ($parentfmt,@parentvars) = $self->SUPER::packFormatAndVars();
    my ($myfmt,@myvars) =
        ("N", 
         \$self->{mSourceSeqno}
        );

    return ($parentfmt.$myfmt,
            @parentvars, @myvars);
}

##VIRTUAL
sub validate {
    my ($self) = @_;
    my $ret = $self->SUPER::validate();
    return $ret if defined $ret;
    return "Bad SR C command '$self->{mCmd}'"
        unless $self->{mCmd} eq "C";
    return "Bad seqno"
        unless $self->{mSourceSeqno} >= 0;
    return undef;
}

##VIRTUAL
sub deliverLocally {
    my __PACKAGE__ $self = shift || die;
    my SRManager $srm = shift || die;
    my $from = $self->{mRoute};
    atEndOfRoute($from) or
        return DPSTD("Not at end, dropped ".$self->summarize());
    my $ssre = $srm->getServerIfAny($from);
    if (defined($ssre)) {
        $ssre->acceptConnection($from,$self->{mSourceSeqno});
        DPSTD("ACCEPTED CONNECTION FROM $from");
    } else {
        my $rpkt = PacketSR_R->new();
        $rpkt->init(SR_RESULT_CONNREFUSED,0);
        $srm->sendSR($rpkt,reverseRoute($from));
        DPSTD("REFUSED CONNECTION FROM $from");
    }
}

1;

