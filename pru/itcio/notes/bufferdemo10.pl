#!/usr/bin/perl -Tw

my $SIZE_BITS = 5; # 9 IRL

my %orb = (
    writePtr => 0,
    readPtr => 0,
    bits => $SIZE_BITS,
    bufsiz => 1<<$SIZE_BITS,
    buff => " "x(1<<$SIZE_BITS)
    );

sub usedBytes {
    my $or = shift;
    my $diff = $or->{writePtr} - $or->{readPtr};
    $diff += $or->{bufsiz} if $diff < 0;
    return $diff;
}

sub availableBytes {
    my $or = shift;
    return $or->{bufsiz} - usedBytes($or) - 1;
}

sub storeByte {
    my ($or,$byte) = @_;
    die unless availableBytes($or);
    die unless length($byte) == 1;
    substr($or->{buff}, $or->{writePtr}, 1) = $byte;
    if (++$or->{writePtr} >= $or->{bufsiz}) {
        $or->{writePtr} = 0;
    }
}

sub addPacket {
    my ($or, $str) = @_;
    my $len = length($str);
    die unless $len > 0;
    die if $len > 255;
    my $avail = availableBytes($or);
    return 0 if ($len >= $avail);
    storeByte($or, chr($len)); # length first
    for (my $i = 0; $i < $len; ++$i) {
        storeByte($or, substr($str,$i,1))
    }
}

sub frontPacketLen {
    my $or = shift;
    return 0 if (usedBytes($or) == 0);
    my $len = ord(substr($or->{buff},$or->{readPtr},1));
    die unless usedBytes($or) > $len; # must be at least one more
    return $len;
}

sub dropFrontPacket {
    my $or = shift;
    die unless usedBytes($or);
    my $len = frontPacketLen($or);
    $or->{readPtr} = ($or->{readPtr} + $len + 1)&($or->{bufsiz}-1);
}

sub frontPacketStartAddress {
    my $or = shift;
    return 0 if (usedBytes($or) == 0);
    return $or->{readPtr}+1;
}

sub getFrontPacketByte {
    my ($or, $lidx) = @_;
    my $base = frontPacketStartAddress($or);
    my $pidx = ($base + $lidx)&($or->{bufsiz}-1);
    return substr($or->{buff},$pidx,1);
}

sub mapstrbuff {
    my $or = shift;
    my $str = $or->{buff};
    $str =~ s/[^[:print:]]/./g;
    my $w = $or->{writePtr};
    my $r = $or->{readPtr};
    ++$w if ($r < $w);
    substr($str,$r,0) = "<";
    substr($str,$w,0) = ">";
    return $str;
}
sub stringORB {
    my $or = shift;
    my $u = usedBytes($or);
    my $s = sprintf("%2dw %2dr %2du %2da",
                    $or->{writePtr},$or->{readPtr},
                    usedBytes($or),availableBytes($or));
    if ($u > 0) {
        $s .= sprintf(" %2dl %2db [%s]", 
                      frontPacketLen($or),
                      frontPacketStartAddress($or),
                      mapstrbuff($or));
        
    }
    return $s;
}

my $or = \%orb;

print stringORB($or)."\n";
addPacket($or, "12345678");
print stringORB($or)."\n";
addPacket($or, "abcdefghij");
print stringORB($or)."\n";
addPacket($or, "klmnopqrstuvwxyz"); # doesn't fit
print stringORB($or)."\n";
dropFrontPacket($or);
print stringORB($or)."\n";
addPacket($or, "klmnopqrstuvwxyz"); # now fits
print stringORB($or)."\n";
addPacket($or, "ABC");              # doesn't fit
print stringORB($or)."\n";
addPacket($or, "AB");               # barely fits
print stringORB($or)."\n";
dropFrontPacket($or);
print stringORB($or)."\n";
dropFrontPacket($or);
print stringORB($or)."\n";
addPacket($or, "012345678901234567890123456");
print stringORB($or)."\n";

