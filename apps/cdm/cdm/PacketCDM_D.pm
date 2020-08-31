## Module stuff
package PacketCDM_D; 
use strict;
use base 'PacketCDM';
use fields qw(
    mSKU
    mStartingIndex
    mData
    mHack16
    );

use Exporter qw(import);

our @EXPORT_OK = qw();
our %EXPORT_TAGS;

## Imports
use Constants qw(:all);
use DP qw(:all);
use T2Utils qw(:all);

BEGIN { push @Packet::PACKET_CLASSES, __PACKAGE__ }

## Methods
sub new {
    my ($class) = @_;
    my $self = fields::new($class);
    $self->SUPER::new();
    $self->{mCmd} = "D";
    return $self;
}

### CLASS METHOD
sub recognize {
    my ($class,$packet) = @_;
    return $class->SUPER::recognize($packet)
        && $packet =~ /^..D/;
}

##VIRTUAL
sub packFormatAndVars {
    my ($self) = @_;
    my ($parentfmt,@parentvars) = $self->SUPER::packFormatAndVars();
    my ($myfmt,@myvars) =
        ("C/a* C/a* C/a* C/a*", 
         \$self->{mSKU},
         \$self->{mStartingIndex},
         \$self->{mData},
         \$self->{mHack16} 
        );

    return ($parentfmt.$myfmt,
            @parentvars, @myvars);
}

##VIRTUAL
sub validate {
    my ($self) = @_;
    my $ret = $self->SUPER::validate();
    return $ret if defined $ret;
    return "Bad D command '$self->{mCmd}'"
        unless $self->{mCmd} eq "D";
    return "Missing SKU in C packet"
        unless length($self->{mSKU}) > 0;
    return "Bad starting index '$self->{mStartingIndex}'"
        unless length($self->{mStartingIndex}) > 0;
    return "Missing data'"
        unless defined($self->{mData});
    return "Bad hack16"
        unless length($self->{mHack16}) > 0;
    return undef;
}

##VIRTUAL
sub handleInbound {
    my __PACKAGE__ $self = shift or die;
    my CDM $cdm = shift or die;
    my $tm = $cdm->{mTraditionalManager} or die;
    return $tm->handleDataChunk($self); 
}

1;

