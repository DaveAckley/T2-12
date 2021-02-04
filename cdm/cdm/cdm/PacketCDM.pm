## Module stuff
package PacketCDM; 
use strict;
use base 'Packet';
use fields qw(
    mCDMCmd
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
    my PacketCDM $self = shift;
    unless (ref $self) {
        $self = fields::new($self);
    }
    $self->SUPER::new();
    $self->{mCDMCmd} = 0x83;
    $self->{mCmd} = chr(0x00); # Set by subclasses
    return $self;
}

### CLASS METHOD
sub recognize {
    my ($class,$packet) = @_;
    return $packet =~ /^[\x80-\x87]\x83/;
}

##VIRTUAL
sub packFormatAndVars {
    my ($self) = @_;
#    DPSTD("INITOFNO2P $self>>".$self->{mCDMCmd} );
    my ($parentfmt,@parentvars) = $self->SUPER::packFormatAndVars();
    my ($myfmt,@myvars) =
        ("C1 A1",
         \$self->{mCDMCmd},
         \$self->{mCmd}
        );

    return ($parentfmt.$myfmt,
            @parentvars, @myvars);
}

##VIRTUAL
sub validate {
    my __PACKAGE__ $self = shift;
    ref $self or die "($self) WHA?";
#DPSTD("VVV1($self)");   
    my $ret = $self->SUPER::validate();
#DPSTD("VVV2($self)");   
    return $ret if defined $ret;
#DPSTD("VVV3($self)");   
    return sprintf("Bad CDM header '0x%02x'", $self->{mCDMCmd})
        unless $self->{mCDMCmd} == 0x83;
#DPSTD("VVV4($self)");   
    return undef;
}


1;

