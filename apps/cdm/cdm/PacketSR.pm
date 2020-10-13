## Module stuff
package PacketSR; 
use strict;
use base 'Packet';
use fields qw(
    mRoute
    mCmd
    );

use Exporter qw(import);

our @EXPORT_OK = qw();
our %EXPORT_TAGS;

## Imports
use Constants qw(:all);
use DP qw(:all);
use T2Utils qw(:all);

## Methods
sub new {
    my PacketSR $self = shift;
    unless (ref $self) {
        $self = fields::new($self);
    }
    $self->SUPER::new();
    $self->{mRoute} = undef; # Illegal value
    $self->{mCmd} = undef;   # Set by subclasses
    return $self;
}

### CLASS METHOD
sub recognize {
    my ($class,$packet) = @_;
    return $packet =~ /^[\x80-\x87][\xb0-\xb8]/;
}

##VIRTUAL
sub prepack {
    my __PACKAGE__ $self = shift or die;
    $self->{mRoute} = encodeRoute($self->{mRoute});
}

##VIRTUAL METHOD
sub postunpack {
    my __PACKAGE__ $self = shift or die;
    $self->{mRoute} = decodeRoute($self->{mRoute});
}

##VIRTUAL
sub packFormatAndVars {
    my ($self) = @_;
    my ($parentfmt,@parentvars) = $self->SUPER::packFormatAndVars();
    my ($myfmt,@myvars) =
        ("Z* A1",
         \$self->{mRoute},
         \$self->{mCmd}
        );

    return ($parentfmt.$myfmt,
            @parentvars, @myvars);
}

##VIRTUAL
sub validate {
    my __PACKAGE__ $self = shift;
    ref $self or die "($self) WHA?";
    my $ret = $self->SUPER::validate();
    return $ret if defined $ret;
    return "Bad route"
        unless defined($self->{mRoute}) && length($self->{mRoute}) > 0;
    return undef;
}

##VIRTUAL
sub handleInbound {
    my __PACKAGE__ $self = shift;
    my CDM $cdm = shift;
    my $route = $self->{mRoute};
    my ($to,$here,$from) = unpackRoute($route);
    return DPSTD("Bad route '$route' in ".$self->summarize())
        unless defined $from;
    DPSTD("SRhIB:$self->{mCmd}/$route=($to,$here,$from)+".
          (defined($self->{mPacketBytes}) ? length($self->{mPacketBytes}) : "(not packed)"));

    # Dish for terminal packets
    return $self->deliverLocally($cdm->{mSRManager}) if $to eq ""; 

    # Else forward
    $to =~ /^([0-7])([0-7]*)$/ or die;           
    my ($dir8,$rest) = (ord($1)-ord('0'),$2);

    my $dir6 = mapDir8ToDir6($dir8);
    return DPSTD("Dropping NT/ST source route ".$self->{mRoute})
        unless defined $dir6;

    my $revdir8 = ($dir8+4)%8;
    my $newroute = $rest."8".chr($revdir8+ord('0')).$from;
    $self->{mRoute} = $newroute;

    $self->setDir8($dir8);           # Update destination

    my $pio = $cdm->getPIO();
    my $ret = $self->sendVia($pio);  # Forward to next stop
    DPSTD("SR send ".$self->summarize()); # self packed by sendVia, can now summarize

    DPSTD("Send failed for ".$self->summarize()) unless $ret;
}

##VIRTUAL
sub deliverLocally {
    my __PACKAGE__ $self = shift || die;
    my SRManager $srm = shift || die;
    DPSTD("Undelivered ".$self->summarize());
}

1;

