## Module stuff
package PacketSR_Qq; # Source route client->server (Q) or server->client (q) quit notification
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

    my $seqno = $sre->{mOurStartSeqno};
    $seqno >= 0 or die;

    my $pkt = PacketSR_Qq->new();
    $pkt->{mCmd} = $sre->{mIsClient} ? "Q" : "q";
    $pkt->{mRoute} = $route;
    $pkt->{mSourceSeqno} = $seqno;
    return $pkt;
}

## Methods
sub new {
    my ($class) = @_;
    my $self = fields::new($class);
    $self->SUPER::new();
    $self->{mCmd} = undef;          # Illegal value
    $self->{mSourceSeqno} = -1;     # Illegal value

    return $self;
}

### CLASS METHOD
sub recognize {
    my ($class,$packet) = @_;
    return $class->SUPER::recognize($packet)
        && $packet =~ /^.[^\x00]*\x00[Qq]/;  # Urgh
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
    return "Bad SR Q command '$self->{mCmd}'"
        unless $self->{mCmd} eq "Q";
    return "Bad seqno"
        unless $self->{mSourceSeqno} >= 0;
    return undef;
}

##VIRTUAL
sub deliverLocally {
    my __PACKAGE__ $self = shift || die;
    my SRManager $srm = shift || die;
    my $toserver = ($self->{mCmd} eq "Q");
    my $from = $self->{mRoute};
    atEndOfRoute($from) or
        return DPSTD("Not at end, dropped ".$self->summarize());

    my $ssre;
    if ($toserver) {
        $ssre = $srm->getServerIfAny($from);
    } else {
        $ssre = $srm->getClientIfAny($from);
    }
    return $ssre->handleQuit($from)
        if defined $ssre;
    DPSTD("No endpoint, dropping ".$self->summarize());
}

1;

