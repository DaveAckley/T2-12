## Module stuff
package PacketIO;
use strict;
use base 'TimeoutAble';
use fields qw(
    mPktHandle
    mOutboundPackets
    );

use Exporter qw(import);

our @EXPORT_OK = qw();
our %EXPORT_TAGS;

## Imports
use Fcntl;
use Constants qw(:all);
use DP qw(:all);
use T2Utils qw(:all);
use Packet;

use constant BULK_PACKET_DEVICE => "/dev/itc/bulk";
use constant BULK_PACKET_MODE => O_RDWR|O_NONBLOCK;

## Methods
sub new {
    my ($class,$cdm) = @_;
    defined $cdm or die;
    my $self = fields::new($class);
    $self->SUPER::new(__PACKAGE__,$cdm);
    $self->{mPktHandle} = undef;
    $self->{mOutboundPackets} = [];
    
    $cdm->getTQ()->schedule($self,0);
    $self->defaultInterval(-0.25);

    return $self;
}

sub init {
    my ($self) = @_;
    sysopen($self->{mPktHandle}, BULK_PACKET_DEVICE, BULK_PACKET_MODE)
        or die "Can't open ".BULK_PACKET_DEVICE.": $!";
    DPSTD("Opened ".BULK_PACKET_DEVICE);
    my ($pkts,$len)=(0,0);
    while ( my $pkt = $self->readPacket() ) {
        ++$pkts;
        $len += length($pkt);
    }
    DPSTD("Discarded $pkts packet(s) containing $len byte(s)");
}

sub readPacket {
    my ($self) = @_;
    my $pkt;
    my $count;
    if (defined($count = sysread($self->{mPktHandle}, $pkt, 512))) {
        return undef if $count == 0;
#        DPPKT("GOT PACKET[$count]($pkt)");
        return $pkt;
    }
    return undef;
}

sub writePacket {
    my ($self,$pkt) = @_;
    push @{$self->{mOutboundPackets}}, $pkt;
    $self->tryFlushOutboundPackets();
}

sub tryFlushOutboundPackets {
    my ($self) = @_;
    my $oref = $self->{mOutboundPackets};
    while (scalar(@{$oref}) > 0) {
        my $pkt = $oref->[0];
        DPSTD(Packet::summarizeString($pkt)." GO");
        my $len = syswrite($self->{mPktHandle}, $pkt);
        if (defined($len) || $!{EHOSTUNREACH}) {
            DPPKT("Host unreachable, pkt dropped") if $!{EHOSTUNREACH};
            shift @{$oref};
            next;
        }
        die "Error: $!" unless $!{EAGAIN};
        DPVRB("WRITE BLOCKING: ".scalar(@{$oref})." packet(s) pending");
        last;
    }
}

sub onTimeout {
    my ($self) = @_;
    DPPushPrefix($self->getTag());
    $self->processPackets();
    $self->tryFlushOutboundPackets();
    DPPopPrefix();
}

sub processPacket {
    my ($self,$dir,$cmd,$rest) = @_;
    my $dirname = getDir8Name($dir);
    DPPKT("proPkt $dirname $cmd +".length($rest));
    return 1;
}

sub dispatchPacket {
    my ($self,$pkt) = @_;
    die unless defined $pkt;
    my $packet = Packable::parse($pkt);
    return DPSTD("Parse failed") unless defined $packet;
    DPPKT("< ".$packet->summarize());
    return $packet->handleInbound($self->{mCDM});
}

sub processPackets {
    my ($self) = @_;
    while (defined(my $pkt = $self->readPacket())) {
        $self->dispatchPacket($pkt);
    }
}

1;
