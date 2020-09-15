## Module stuff
package PacketCDM_A; 
use strict;
use base 'PacketCDM';
use fields qw(
    mRollingTag
    mOptVersion
    );

use Exporter qw(import);

our @EXPORT_OK = qw();
our %EXPORT_TAGS;

## Imports
use Constants qw(:all);
use DP qw(:all);
use T2Utils qw(:all);

BEGIN { push @Packable::PACKABLE_CLASSES, __PACKAGE__ }

## Methods
sub new {
    my ($class) = @_;
    my $self = fields::new($class);
    $self->SUPER::new();
    $self->{mCmd} = "A";
    $self->{mRollingTag} = -1; # Illegal value
    $self->{mOptVersion} = ""; # If not overridden
    return $self;
}

### CLASS METHOD
sub recognize {
    my ($class,$packet) = @_;
    return $class->SUPER::recognize($packet)
        && $packet =~ /^..A/;
}

##VIRTUAL
sub packFormatAndVars {
    my ($self) = @_;
    my ($parentfmt,@parentvars) = $self->SUPER::packFormatAndVars();
    my ($myfmt,@myvars) =
        ("C1 a*", 
         \$self->{mRollingTag},
         \$self->{mOptVersion}
        );

    return ($parentfmt.$myfmt,
            @parentvars, @myvars);
}

sub getVersion {
    my ($self) = @_;
    return CDM_PROTOCOL_VERSION_ASPINNER
        if $self->{mOptVersion} eq "";
    return ord($self->{mOptVersion});
}

sub setOptVersion {
    my ($self,$version) = @_;
    die if $version < 0 || $version > 255;
    $self->{mOptVersion} =
        ($version <= CDM_PROTOCOL_VERSION_ASPINNER) ? "" : chr($version);
}

##VIRTUAL
sub validate {
    my ($self) = @_;
    my $ret = $self->SUPER::validate();
    return $ret if defined $ret;
    return "Bad A command '$self->{mCmd}'"
        unless $self->{mCmd} eq "A";
    return "Missing tag in A packet"
        unless $self->{mRollingTag} >= 0;
    return undef;
}

##VIRTUAL
sub handleInbound {
    my ($self,$cdm) = @_;
    my $nm = $self->getNMIfAny($cdm);
    return DPSTD("No NM for ".$self->summarize())
        unless $nm;
    $nm->bump();  # They're alive
    $nm->theirVersion($self->getVersion());
}

1;

