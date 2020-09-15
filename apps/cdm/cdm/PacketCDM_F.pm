## Module stuff
package PacketCDM_F;  # New style file announcement
use strict;
use base 'PacketCDM';
use fields qw(
    mSlotStamp
    mAvailableLength
    mChecksum
    );

use Exporter qw(import);

our @EXPORT_OK = qw();
our %EXPORT_TAGS;

## Imports
use Constants qw(:all);
use DP qw(:all);
use T2Utils qw(:all);
use MFZModel;

BEGIN { push @Packable::PACKABLE_CLASSES, __PACKAGE__ }

## Methods
sub new {
    my ($class) = @_;
    my $self = fields::new($class);
    $self->SUPER::new();
    $self->{mCmd} = "F";
    $self->{mSlotStamp} = 0;       # Illegal value
    $self->{mAvailableLength} = 0; # Illegal value -- you can't advertise with <1KB
    $self->{mChecksum} = -1;       # Incorrect checksum
    return $self;
}

### CLASS METHOD
sub makeFromMFZModel {
    my $class = shift || die;
    my MFZModel $model = shift || die;
    my $available = $model->servableLength() || return undef;
    my $fpkt = $class->new();
    $fpkt->{mSlotStamp} = $model->{mSlotStamp};
    $fpkt->{mAvailableLength} = $available;
    $fpkt->pack();
    return $fpkt;
}

### CLASS METHOD
sub recognize {
    my ($class,$packet) = @_;
    return $class->SUPER::recognize($packet)
        && $packet =~ /^..F/;
}

##VIRTUAL
sub prepack {
    my __PACKAGE__ $self = shift or die;
    $self->{mChecksum} = $self->{mSlotStamp} ^ $self->{mAvailableLength};
}

##VIRTUAL
sub packFormatAndVars {
    my __PACKAGE__ $self = shift;
    my ($parentfmt,@parentvars) = $self->SUPER::packFormatAndVars();
    my ($myfmt,@myvars) =
        ("NNN",
         \$self->{mSlotStamp},
         \$self->{mAvailableLength},
         \$self->{mChecksum}
        );

    return ($parentfmt.$myfmt,
            @parentvars, @myvars);
}

##VIRTUAL
sub validate {
    my __PACKAGE__ $self = shift;
    my $ret = $self->SUPER::validate();
    return $ret
        if defined $ret;
    return "Bad F command '$self->{mCmd}'"
        unless $self->{mCmd} eq "F";
    return "Missing slotstamp"
        unless $self->{mSlotStamp} > 0;
    return "Missing available length"
        unless $self->{mAvailableLength} > 0;
    return "Checksum failure"
        unless $self->{mChecksum} == ($self->{mSlotStamp} ^ $self->{mAvailableLength});
    return undef;
}

##VIRTUAL
sub handleInbound {
    my __PACKAGE__ $self = shift;
    my CDM $cdm = shift;
    my $cmgr = $cdm->{mContentManager} or die;
    return $cmgr->updateMFZModelAvailability($self); 
}

1;

