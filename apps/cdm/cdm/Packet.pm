## Module stuff
package Packet;
use strict;
use fields qw(
    mPacketBytes
    mPacketLength
    mPacketHeader
    );

use Exporter qw(import);

our @EXPORT_OK = qw(parse summarizeString validateAsClass);
our %EXPORT_TAGS;

## Imports
use Constants qw(:all);
use DP qw(:all);
use T2Utils qw(:all);

our @PACKET_CLASSES = qw();

## Methods
sub new {
    my Packet $self = shift;
    unless (ref $self) {
        $self = fields::new($self);
    }
    $self->{mPacketHeader} = 0x80; # std no errors (dir == NT, but whatever)
    return $self;
}

sub rawByte {
    my ($self,$idx,$newbyte) = @_;
    return rawByteOfRef(\$self->{mPacketBytes},$idx,$newbyte);
}

sub getDir8 {
    my ($self) = @_;
    return $self->{mPacketHeader}&0x7;
}

sub setDir8 {
    my ($self,$dir8) = @_;
    $self->{mPacketHeader} = ($self->{mPacketHeader}&~0x7)|($dir8&0x7);
}

sub getNMIfAny {
    my ($self,$cdm) = @_;
    my $dir8 = $self->getDir8();
    my $dir6 = mapDir8ToDir6($dir8);
    return undef unless defined $dir6;
    
    my $hoodmgr = $cdm->{mNeighborhoodManager};
    die unless defined $hoodmgr;
    return $hoodmgr->ngbMgr($dir6);
}

sub sendVia {
    my __PACKAGE__ $self = shift;
    my PacketIO $pio = shift;
    ref $self or die "SV($self)";
#    DPSTD("sendVia0($self)");
    my $ret = eval {
#    DPSTD("sendVia1($self)");
        $self->pack();
#    DPSTD("sendVia2($self)");
#    DPSTD("sendViaX($self->{mPacketBytes})");
        $pio->writePacket($self->{mPacketBytes});
        DPPKT("> ".$self->summarize());
#    DPSTD("sendVia3");
        1;
    };
#    DPSTD("sendVia ret ($ret)") if defined $ret;
    DPSTD("sendVia failed ($@)") unless defined $ret;
    $ret;
}

##VIRTUAL
sub packFormatAndVars {
    my ($self) = @_;
    return ("C1",\$self->{mPacketHeader});
}

##VIRTUAL
sub validate {
    my __PACKAGE__ $self = shift;
    ## return undef if all is valid, else an error message
    ## subclasses do something like
    ##   my $ret = $self->SUPER::validate();
    ##   return $ret if defined $ret;
    ##   # per-class checks here
    ##   return undef;  # if all is okay
    return undef;
}

##VIRTUAL
sub handleInbound {  # Respond to this packet via side effects
    my ($self,$cdm) = @_;
    return DPSTD("No inbound handler for ".$self->summarize());
}

##CLASS: Return true to declare this packet is yours
sub recognize {
    my ($class,$packet) = @_;
    return undef;
}

use Data::Dumper;
sub unpack {
    my ($self) = @_;
    my ($fmt,@varrefs) = $self->packFormatAndVars();
    my @values = unpack($fmt,$self->{mPacketBytes});
    for (0 .. $#varrefs) {
        ${$varrefs[$_]} = $values[$_];
    }
#    DPSTD("QQUNPACK($self)");
    my $ret = $self->validate();
    die "Unpacked packet failed validation: $ret" if defined $ret;
}

sub pack {
    my __PACKAGE__ $self = shift;
    my ($fmt,@varrefs) = $self->packFormatAndVars();
    my @values = map { $$_ } @varrefs;
#    print Dumper(\$fmt);
#    print Dumper(\@varrefs);
#    print Dumper(\@values);
    $self->{mPacketBytes} = pack($fmt, @values);
    $self->{mPacketLength} = length($self->{mPacketBytes});
#    DPSTD("QQPACK($self)");
    my $ret = $self->validate();
    die "Packed packet failed validation: $ret" if defined $ret;
}

### CLASS METHOD
sub rawByteOfRef {
    my ($pref,$idx,$newbyte) = @_;
    return undef if $idx < 0 || $idx >= length($$pref);
    my $byte = substr($$pref,$idx,1);
    return $byte
        unless defined($newbyte);
    substr($$pref,$idx,1) = $newbyte;
}

sub summarize {
    my ($self) = @_;
    return summarizeString($self->{mPacketBytes});
}

### CLASS METHOD
sub validateAsClass {
    my $class = shift;
    my Packet $pkt = shift;
    return ($@ = "Undefined class", undef)  unless defined $class;
    return ($@ = "Undefined packet", undef) unless defined $pkt;
    return ($@ = "Not a $class", undef)     unless $pkt->isa($class);
    my $ret = $pkt->validate();
    return ($@ = $ret, undef)               if defined $ret;
    return $pkt;
}

### CLASS METHOD
sub assertValid {
    my ($class,$pkt) = @_;
    die "Invalid $class: $@" unless $class->validateAsClass($pkt);
    return $pkt;
}

### CLASS METHOD
sub summarizeString {
    my ($packet) = @_;
    return "Undef" unless defined $packet;
    my $len = length($packet);
    return "Empty" if $len == 0;
    my $hdr = rawByteOfRef(\$packet,0);
    return "Non-standard '$hdr'+$len" unless (ord($hdr)&0x80);
    my $dir8 = ord($hdr)&0x7;
    my $dir8name = getDir8Name($dir8);
    return "$dir8name MFM + $len" if (ord($hdr)&0x20);
    return "Service + $len" if $len < 2;
    my $byte1 = rawByteOfRef(\$packet,1);
    return "$dir8name '$byte1' flash + $len" unless (ord($byte1)&0x80);
    my $bulkcode = ord($byte1)&0x7f;
    return "$dir8name bulk code $bulkcode + $len" unless ($bulkcode == 3);
    return "$dir8name CDM + $len" if $len < 3;
    my $byte2 = rawByteOfRef(\$packet,2);
    return "$dir8name CDM '$byte2' + $len";
}

### CLASS METHOD
sub parse {
    my ($packet) = @_;
    my $len = length($packet);
    for my $pkg (@PACKET_CLASSES) {
        my $rec = $pkg->recognize($packet);
        if ($rec) {
            my $pself = $pkg->new();
            $pself->{mPacketBytes} = $packet;
            $pself->{mPacketLength} = $len;
            my $ret = eval {
                $pself->unpack();
                $pself;
            };
            return $ret;
        }
    }
    DPSTD("Unrecognized ".summarizeString($packet)." packet, ignored");
    return undef;
}

1;
