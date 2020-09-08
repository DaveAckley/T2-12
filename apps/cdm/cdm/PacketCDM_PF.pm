## Module stuff
package PacketCDM_PF; 
use strict;
use base 'PacketCDM_P';
use fields qw(
    mOutboundTag
    mFileTotalLength
    mFileTotalChecksum
    mSPacketBytes
    mSPacket
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
    my PacketCDM_S $spkt = shift; ## UNDEF OKAY
    my $self = fields::new($class);
    $self->SUPER::new();
    $self->{mPipelineCmd} = "F";
    $self->{mOutboundTag} = 0;     # Illegal value
    $self->{mFileTotalLength} = 0; # Illegal value
    $self->{mFileTotalChecksum} = "";
    $self->{mSPacketBytes} = "";
    $self->{mSPacket} = $spkt;
    return $self;
}

### CLASS METHOD
sub recognize {
    my ($class,$packet) = @_;
    return $class->SUPER::recognize($packet)
        && $packet =~ /^...F/;
}

##VIRTUAL
sub packFormatAndVars {
    my ($self) = @_;
    my ($parentfmt,@parentvars) = $self->SUPER::packFormatAndVars();
    my ($myfmt,@myvars) =
        ("NN a16 a".ANNOUNCE_PACKET_LENGTH, 
         \$self->{mOutboundTag},
         \$self->{mFileTotalLength},
         \$self->{mFileTotalChecksum},
         \$self->{mSPacketBytes}
        );

    return ($parentfmt.$myfmt,
            @parentvars, @myvars);
}

##VIRTUAL METHOD
sub prepack {
    my PacketCDM_PF $self = shift or die;
    $self->SUPER::prepack();
    $self->{mSPacket}->pack();
    $self->{mSPacketBytes} = $self->{mSPacket}->{mPacketBytes};
}

##VIRTUAL METHOD
sub postunpack {
    my PacketCDM_PF $self = shift or die;
    $self->SUPER::postunpack();
    $self->{mSPacket} = Packet::parse($self->{mSPacketBytes});
}

##VIRTUAL
sub validate {
    my PacketCDM_PF $self = shift or die;
    my $ret = $self->SUPER::validate();
    return $ret if defined $ret;
    return "Bad PF command in P packet"
        unless $self->{mPipelineCmd} eq "F";
    return "Illegal outbound tag"
        unless $self->{mOutboundTag} > 0;
    return "Illegal file length"
        unless $self->{mFileTotalLength} > 0;
    return "Misformatted S packet"
        unless length($self->{mSPacketBytes}) == ANNOUNCE_PACKET_LENGTH
        and PacketCDM_S->recognize($self->{mSPacketBytes});
    return undef;
}

##VIRTUAL
sub handleInbound {
    my __PACKAGE__ $self = shift;
    my CDM $cdm = shift;
    my $tm = $cdm->{mPipelineManager} or die;
    return $tm->handleAnnouncement($self); 
}

1;

