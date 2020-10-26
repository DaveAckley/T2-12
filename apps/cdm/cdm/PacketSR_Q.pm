## Module stuff
package PacketSR_Q; # Source route client<->server quit notification
use strict;
use base 'PacketSR';
use fields qw(
    mFlags
    mStatus
    );

## Imports
use Constants qw(:all);
use DP qw(:all);
use T2Utils qw(:all);

use PacketSR_R;

use Exporter qw(import);

our @EXPORT_OK = qw();
our %EXPORT_TAGS;

BEGIN { push @Packable::PACKABLE_CLASSES, __PACKAGE__ }

### CLASS METHOD

## Methods
sub new {
    my ($class) = @_;
    my $self = fields::new($class);
    $self->SUPER::new();
    $self->{mCmd} = "Q";   
    $self->{mFlags} = 0;        # Default value
    $self->{mStatus} = undef;   # Illegal value

    return $self;
}

### CLASS METHOD
sub recognize {
    my ($class,$packet) = @_;
    return $class->SUPER::recognize($packet)
        && $packet =~ /^.[^\x00]*\x00[Q]/;  # Urgh
}

##VIRTUAL
sub packFormatAndVars {
    my ($self) = @_;
    my ($parentfmt,@parentvars) = $self->SUPER::packFormatAndVars();
    my ($myfmt,@myvars) =
        ("C C", 
         \$self->{mFlags},
         \$self->{mStatus}
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
    return "Bad status"
        unless $self->{mStatus} >= 0 && $self->{mStatus} < (1<<8);
    return undef;
}

##VIRTUAL
sub deliverLocally {
    my __PACKAGE__ $self = shift || die;
    my EPManager $srm = shift || die;
    my $toserver = ($self->{mFlags} & Q_PKT_FLAG_TO_SERVER)!=0;
    my $from = $self->{mRoute};
    atEndOfRoute($from) or
        return DPSTD("Not at end, dropped ".$self->summarize());

    my $ep;
    if ($toserver) {
        $ep = $srm->getServerIfAny($from);
    } else {
        $ep = $srm->getClientIfAny($from);
    }
    return $ep->handleQuit($self)
        if defined $ep;
    DPSTD("No endpoint, dropping ".$self->summarize());
}

1;

