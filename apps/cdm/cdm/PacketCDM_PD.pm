## Module stuff
package PacketCDM_PD; 
use strict;
use base 'PacketCDM_P';
use fields qw(
    mOutboundTag
    mFilePosition
    mDataChunk
    mXsumOpt
    );

use Exporter qw(import);

our @EXPORT_OK = qw();
our %EXPORT_TAGS;

## Imports
use Constants qw(:all);
use DP qw(:all);
use T2Utils qw(:all);
use PacketCDM_S;

BEGIN { push @Packet::PACKET_CLASSES, __PACKAGE__ }

## Methods
sub new {
    my $class = shift or die;
    my $self = fields::new($class);
    $self->SUPER::new();
    $self->{mPipelineCmd} = "D";
    $self->{mOutboundTag} = 0;     # Illegal value
    $self->{mFilePosition} = -1;   # Illegal value
    $self->{mDataChunk} = undef;
    $self->{mXsumOpt} = undef;
    return $self;
}

### CLASS METHOD
sub recognize {
    my ($class,$packet) = @_;
    return $class->SUPER::recognize($packet)
        && $packet =~ /^...D/;
}

##VIRTUAL
sub packFormatAndVars {
    my ($self) = @_;
    my ($parentfmt,@parentvars) = $self->SUPER::packFormatAndVars();
    my ($myfmt,@myvars) =
        ("NN C/a* c/a*", 
         \$self->{mOutboundTag},
         \$self->{mFilePosition},
         \$self->{mDataChunk},
         \$self->{mXsumOpt}
        );

    return ($parentfmt.$myfmt,
            @parentvars, @myvars);
}

##VIRTUAL METHOD
sub prepack {
    my PacketCDM_PD $self = shift or die;
    $self->SUPER::prepack();
    $self->{mXsumOpt} = "" unless defined $self->{mXsumOpt};
}

##VIRTUAL METHOD - Nothing to do
# sub postunpack {
#     my PacketCDM_PD $self = shift or die;
#     $self->SUPER::postunpack();
# }

##VIRTUAL
sub validate {
    my PacketCDM_PD $self = shift or die;
    my $ret = $self->SUPER::validate();
    return $ret if defined $ret;
    return "Bad PD command in P packet"
        unless $self->{mPipelineCmd} eq "D";
    return "Illegal outbound tag"
        unless $self->{mOutboundTag} > 0;
    return "Illegal file position"
        unless $self->{mFilePosition} >= 0;
    return undef;
}

##VIRTUAL
sub handleInbound {
    my __PACKAGE__ $self = shift;
    my CDM $cdm = shift;
    my $tm = $cdm->{mPipelineManager} or die;
    return $tm->handlePipelineChunkData($self); 
}

1;

