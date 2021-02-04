## Module stuff
package PacketSR_R;  # Source route server->client connection reply
use strict;
use base 'PacketSR';
use fields qw(
    mResult
    mSourceSeqno
    );

## Imports
use Constants qw(:all);
use DP qw(:all);
use T2Utils qw(:all);

use EPManager;

use Exporter qw(import);

our @EXPORT_OK = qw();
our %EXPORT_TAGS;

BEGIN { push @Packable::PACKABLE_CLASSES, __PACKAGE__ }

## Methods
sub new {
    my ($class) = @_;

    my __PACKAGE__ $self = fields::new($class);
    $self->SUPER::new();
    $self->{mCmd} = "R";            # We are an SR R packet
    $self->{mResult} = -1;          # Illegal value
    $self->{mSourceSeqno} = -1;     # Illegal value

    return $self;
}

sub init {
    my __PACKAGE__ $self = shift || die;
    my $result = shift; defined $result or die;
    my $ourseqno = shift; defined $ourseqno or die;
    $self->{mResult} = $result;
    $self->{mSourceSeqno} = $ourseqno;
}

### CLASS METHOD
sub recognize {
    my ($class,$packet) = @_;
    return $class->SUPER::recognize($packet)
        && $packet =~ /^.[^\x00]*\x00R/;  # Urgh
}

##VIRTUAL
sub packFormatAndVars {
    my ($self) = @_;
    my ($parentfmt,@parentvars) = $self->SUPER::packFormatAndVars();
    my ($myfmt,@myvars) =
        ("C1 N", 
         \$self->{mResult},
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
    return "Bad SR R command '$self->{mCmd}'"
        unless $self->{mCmd} eq "R";
    return "Undefined result"
        unless defined($self->{mResult});
    return "Bad result"
        unless $self->{mResult} >= 0 && $self->{mResult} <= 0xff;
    return "Bad seqno"
        unless $self->{mSourceSeqno} >= 0;
    return undef;
}

##VIRTUAL
sub deliverLocally {
    my __PACKAGE__ $self = shift || die;
    my EPManager $srm = shift || die;
    my $from = $self->{mRoute};
    atEndOfRoute($from) or
        return DPSTD("Not at end, dropped ".$self->summarize());
    my $ep = $srm->getClientIfAny($from);
    if (defined($ep)) {
        $ep->handleResponse($self);
    } else {
        DPSTD("No '$from' client, dropping ".$self->summarize());
    }
}

1;

