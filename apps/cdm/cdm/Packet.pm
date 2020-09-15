## Module stuff
package Packet;
use strict;
use base 'Packable';
use fields qw(
    mPacketHeader
    );

use Exporter qw(import);

our @EXPORT_OK = qw(summarizeString);
our %EXPORT_TAGS;

## Imports
use Constants qw(:all);
use DP qw(:all);
use T2Utils qw(:all);

## Methods
sub new {
    my Packet $self = shift;
    unless (ref $self) {
        $self = fields::new($self);
    }
    $self->SUPER::new();
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
    my __PACKAGE__ $self = shift or die;
    my $pio = shift or die;
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
    my ($parentfmt,@parentvars) = $self->SUPER::packFormatAndVars();
    my ($myfmt,@myvars) =
        ("C1",
         \$self->{mPacketHeader}
        );
    return ($parentfmt.$myfmt,
            @parentvars, @myvars);
}

##VIRTUAL
sub handleInbound {  # Respond to this packet via side effects
    my ($self,$cdm) = @_;
    return DPSTD("No inbound handler for ".$self->summarize());
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

##OVERRIDE METHOD
sub summarize {
    my ($self) = @_;
    return summarizeString($self->{mPacketBytes});
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
    return "$dir8name '$byte1' flash [$len]" unless (ord($byte1)&0x80);
    my $bulkcode = ord($byte1)&0x7f;
    return "$dir8name bulk code $bulkcode [$len]" unless ($bulkcode == 3);
    return "$dir8name CDM [$len]" if $len < 3;
    my $byte2 = rawByteOfRef(\$packet,2);
    if ($len > 3 && $byte2 eq "P") {
        my $byte3 = rawByteOfRef(\$packet,3);
        return "$dir8name CDM_$byte2$byte3 [$len]";
    }
    return "$dir8name CDM_$byte2 [$len]";
}

1;
