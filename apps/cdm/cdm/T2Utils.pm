## Module stuff
package T2Utils;
use strict;

use Exporter qw(import);

my @math = qw(
    ceiling 
    max
    min
    oddsOf
    oneIn
    pickOne
    createNBits
    lexEncode
    lexDecode

    hexEscape
    deHexEscape

    hack16

    now
    ago
    aged

    trim

    formatSeconds
    formatSize
    formatPercent
    );

my @route = qw(
    unpackRoute
    reverseRoute
    toAddressOfRoute
    fromAddressOfRoute
    atStartOfRoute
    atEndOfRoute
    encodeRoute
    decodeRoute
    collapseRouteToCoord
    collapseRouteToEndpointKey
    unpackEndpointKey
    packEndpointKey
    formatEndpointKey
    packCoord
    unpackCoord
    dir8ToCoord
    formatDFlags
);

my @dir6s = qw(
    getDir6Name 
    getDir6Number 
    dir6Iterator 
    getDir6s
    );
my @dir8s = qw(
    getDir8Name 
    getDir8Number 
    dir8Iterator 
    getDir8s
    );
my @dirs = (
    @dir6s,
    @dir8s,
    'mapDir6ToDir8',
    'mapDir8ToDir6'
    );
my @packet = qw(
    makeCDMPacket
    );
my @fileops = qw(
    checksumWholeFile
    initDir
    listDir
    sysreadlineNonblocking
    );
my @processops = qw(
    runCommandWithSync
    );
our @EXPORT_OK = (@math, @dirs, @packet, @route, @fileops, @processops);
our %EXPORT_TAGS = (
    math => \@math,
    dir6s => \@dir6s,
    dir8s => \@dir8s,
    dirs => \@dirs,
    packet => \@packet,
    route => \@route,
    fileops => \@fileops,
    processops => \@processops,
    all => \@EXPORT_OK
    );

## IMPORTS
use List::Util qw(shuffle);
use Digest::SHA qw(sha512_hex);
use Time::HiRes qw(time);
use File::Path qw(make_path);
    
use DP qw(:all);
use Constants qw(:all);

## MATH

sub ceiling {
    my $n = shift;
    return ($n == int $n) ? $n : int($n + 1);
}

sub max {
    my ($n,$m) = @_;
    return ($n >= $m) ? $n : $m;
}

# sub abs {
#     my ($n) = @_;
#     return ($n > 0) ? $n : -$n;
# }

sub min {
    my ($n,$m) = @_;
    return ($n <= $m) ? $n : $m;
}

sub oddsOf {
    my $n = shift;
    my $outof = shift;
    return 1 if $outof <= 1;
    return int(rand($outof)) < $n;
}

sub oneIn {
    return oddsOf(1,shift);
}

sub pickOne {
    my @args = @_;
    my $len = scalar(@args);
    return undef if $len == 0;
    return $args[int(rand($len))];
}

sub createNBits {
    my $bits = shift || 32;
    die if $bits > 48;  # rand starts pooping out?
    return int(rand(1<<$bits));
}

sub lexEncode {
    my $num = shift;
    my $len = length($num);
    return $len.$num if $len < 9;
    return "9".lexEncode($len).$num;
}

sub lexDecode {
    my $lex = shift;
    if ($lex =~ s/^9//) {
        my ($len,$rest) = lexDecode($lex);
        my $num = substr($rest,0,$len);
        substr($rest,0,$len) = "";
        return ($num,$rest);
    } elsif ($lex =~ s/^([0-8])//) {
        my $len = $1;
        my $num = substr($lex,0,$len);
        substr($lex,0,$len) = "";
        return ($num,$lex);
    } else {
        return undef;
    }
}

sub hexEscape {
    my $str = shift;
    $str =~ s/([^-_.a-zA-Z0-9])/sprintf("%%%02x",ord($1))/ge;
    return $str;
}

sub deHexEscape {
    my $str = shift;
    $str =~ s/%([a-fA-f0-9]{2})/chr(hex($1))/ge;
    return $str;
}

sub hack16 {
    my $str = shift;
    my $h = 0xfeed;
    for my $i (0 .. (length ($str) - 1)) {
        $h = (($h<<1)^ord(substr($str,$i,1))^($h>>11))&0xffff;
    }
    return chr(($h>>8)&0xff).chr($h&0xff);
}

sub now {
    return time();
}

sub ago {
    my $when = shift;
    return now() - $when;
}

sub aged {
    my ($when,$age) = @_;
    return ago($when) >= $age;
}

my %units = (
    7*60*60*24 => "w",
    60*60*24 => "d",
    60*60 => "h",
    60 => "m",
    1 => "s",
    );
my @chunks = sort {$b <=> $a} keys %units;

sub trim { $_ = shift;  s/^\s+|\s+$//g; $_}

sub formatSeconds {
    my $sec = shift;
    my $optrim = shift;
    my $neg = "";
    my $ret = "";
    if ($sec < 0) {
        $neg = "-";
        $sec = -$sec;
    }
    return sprintf("%s%.02fs",$neg,$sec)
        if $sec < 1;

    for my $size (@chunks) {
        if ($sec > $size) {
            my $count = int($sec/$size);
            $sec -= $count*$size;
            $ret .= " " if $ret ne "";
            $ret .= "${count}$units{$size}";
        }
    }
    $ret = "$neg$ret";
    $ret = trim($ret) if $optrim;
    return $ret;
}

my @kunits = split(//," KMGTPE");
sub formatSize {
    my $size = shift;
    my $optrim = shift;
    my $ret = "";
    if ($size < 0) {
        $ret = " <0 ";
    } elsif ($size== 0) {
        $ret = "  0 ";
    } else {
        for my $unit (@kunits) {
            if ($size < 1000) {
                if ($size < 1) {
                    $ret = sprintf(".%02d%s",int($size*100),$unit);
                } elsif ($size >= 9.95 || int($size) == $size) {
                    $ret = sprintf("%3d%s", $size+0.5, $unit);
                } else {
                    $ret = sprintf("%3.1f%s",$size,$unit);
                }
                last;
            }
            $size /= 1000.0;
        }
    }
    $ret = trim($ret) if $optrim;
    return $ret;
}

sub formatPercent {
    my $pct = shift;
    my $optrim = shift;
    my $ret;
    if (0) { }
    elsif ($pct <    0) { $ret = " <0%"; }
    elsif ($pct <    1) { $ret = sprintf(".%02d%%",int($pct*100)); }
    elsif ($pct < 9.95) { $ret = sprintf("%3.1f%%",$pct); }
    elsif ($pct <  999) { $ret = sprintf("%3d%%",int($pct+0.5)); }
    else               { $ret = "1K+%"; }
    $ret = trim($ret) if $optrim;
    return $ret;
}


## DIRECTIONS

my %ITCDirs = (
    ET => 0,
    SE => 1,
    SW => 2,
    WT => 3,
    NW => 4,
    NE => 5
    );

my @ITCDirsByIndex = sort { $ITCDirs{$a} <=> $ITCDirs{$b} } keys %ITCDirs;

my %Dir8Dirs = (
    NT => 0,
    NE => 1,
    ET => 2,
    SE => 3,
    ST => 4,
    SW => 5,
    WT => 6,
    NW => 7
    );

my @Dir8DirsByIndex = sort { $Dir8Dirs{$a} <=> $Dir8Dirs{$b} } keys %Dir8Dirs;

sub getDir6Name {
    my $dir6 = shift;
    return $ITCDirsByIndex[$dir6];
}

sub getDir6Number {
    my $dir6name = shift;
    return $ITCDirs{$dir6name};
}

sub dir6Iterator {
    return shuffle(getDir6s());
}

sub getDir6s {
    return 0..5;
}

sub getDir8Name {
    my $dir8 = shift;
    return $Dir8DirsByIndex[$dir8];
}

sub getDir8Number {
    my $dir8name = shift;
    return $Dir8Dirs{$dir8name};
}

sub dir8Iterator {
    return shuffle(getDir8s());
}

sub getDir8s {
    return 0..7;
}

sub mapDir6ToDir8 {
    my $dir6 = shift;
    my $dir6name = getDir6Name($dir6);
    return getDir8Number($dir6name);
}

sub mapDir8ToDir6 {
    my $dir8 = shift;
    my $dir8name = getDir8Name($dir8);
    return getDir6Number($dir8name);  # returns undef on NT/ST
}

sub makeCDMPacket {
    my ($dir8,$cdmCmd,$rest) = @_;
    my $pkt = pack("CCa1a*",(0x80|$dir8),0x83,$cdmCmd,$rest);
    DPSTD("MADE CDM PACKET '$pkt'");
    return $pkt;
}

## FILEOPS

my $digester = Digest::SHA->new(256);
sub checksumWholeFile {
    my $path = shift;
    $digester->reset();
    $digester->addfile($path);
    my $cs = substr($digester->digest(),0,16);
    my $hexcs = unpack("H*",$cs);
    DPVRB(" $path => $hexcs");
    return $cs;
}

# return undef and set $! if dir couldn't be created
sub initDir {
    my $dirpath = shift || die;
    if (!-d $dirpath) {
        make_path($dirpath) or return undef;
    }
    return 1;
}

sub listDir {
    my $dirpath = shift || die;
    opendir my $fh, $dirpath or die "Can't read '$dirpath': $!";
    my @files = readdir $fh;
    closedir $fh or die $!;
    return @files;
}

# return 1 if $$bufref now has complete line
# return 0 if $$bufref not enough data available yet
# return -1 on EOF
# return undef and set $! on error
sub sysreadlineNonblocking {
    my($handle,$bufref) = @_;
    my $wasBlocking = $handle->blocking(0);
    my $result = undef;
    while (1) {
        my $nextbyte;
        my $ret = sysread($handle, $nextbyte, 1);
        if (!defined($ret)) {
            if ($!{EAGAIN}) {  # No more data yet
                $result = 0;
            }  # Else some other error, result stays undef
            last;
        }
        
        if ($ret == 0) {
            $result = -1;
            last;
        }
        $$bufref .= $nextbyte;

        if ($nextbyte eq "\n") {
            $result = 1;
            last;
        }
    }
    $handle->blocking($wasBlocking);
    return $result;
}

##PROCESSOPS

sub runCommandWithSync {
    my ($btcmd,$errprefix) = @_;
    DPPushPrefix($errprefix) if defined $errprefix;
    `$btcmd && sync`; 
    my $ret = $?;
    DPSTD("'$btcmd' returned code $ret") if $ret;
    DPPopPrefix() if defined $errprefix;
    return !$ret;
}

## ROUTE FUNCTIONS
sub unpackRoute {
    my $route = shift || die;
    $route =~ /^([0-7]*)(8)([0-7]*)$/
        or return DPSTD("Bad route '$route'");
    return ($1,$2,$3)
}

sub reverseRoute {
    my $route = shift || die;
    my ($to,$here,$from) = unpackRoute($route);
    return unless defined $from;
    return "$from$here$to";
}

sub toAddressOfRoute {
    my $route = shift || die;
    my ($to,$here,$from) = unpackRoute($route);
    return unless defined $from;
    return $to;
}

sub fromAddressOfRoute {
    my $route = shift || die;
    my ($to,$here,$from) = unpackRoute($route);
    return unless defined $from;
    return $from;
}

sub atStartOfRoute {
    my $route = shift || die;
    my ($to,$here,$from) = unpackRoute($route);
    return unless defined $from;
    return $from eq "" ? 1 : 0;
}

sub atEndOfRoute {
    my $route = shift || die;
    my ($to,$here,$from) = unpackRoute($route);
    return unless defined $from;
    return $to eq "" ? 1 : 0;
}

sub encodeRoute {
    my $route = shift; defined $route or die;
    my $count = $route =~ tr/0-8/\xb0-\xb8/;
    die unless $count == length($route);
    return $route;
}

sub decodeRoute {
    my $route = shift; defined $route or die;
    my $count = $route =~ tr/\xb0-\xb8/0-8/;
    die unless $count == length($route);
    return $route;
}

sub collapseRouteToEndpointKey {
    my $route = shift; defined $route or die;
    my $isclient = atStartOfRoute($route);
    my ($x,$y) = collapseRouteToCoord($route);
    return packEndpointKey($isclient,$x,$y);
}

sub packEndpointKey {
    my ($isclient,$x,$y) = @_;
    return pack("ccc",$isclient,$x,$y);
}

sub unpackEndpointKey {
    my $ekey = shift || die;
    return unpack("ccc",$ekey);
}

sub formatEndpointKey {
    my ($isclient,$x,$y) = unpackEndpointKey(shift);
    return "invalid" unless defined($y);
    return ($isclient ? "c" : "s")."($x,$y)";
}

sub collapseRouteToCoord {
    my $route = shift; defined $route or die;
    my ($x,$y) = (0,0);
    for my $stop (split(//,$route)) {
        my ($dx,$dy) = dir8ToCoord($stop);
        die "Illegal dir8 '$stop' in '$route'"
            unless defined $dy;
        $x += $dx;
        $y += $dy;
    }
    die "|($x,$y)| too large"
        if abs($x) > 127 || abs($y) > 127;
    return ($x,$y);
}

sub packCoord {
    my ($x,$y) = @_;
    die unless defined $x && defined $y;
    return pack("c1 c1", $x, $y);
}

sub unpackCoord {
    my $c = shift || die;
    return unpack("c1 c1", $c);
}

sub dir8ToCoord {
    my $dir8 = shift; defined $dir8 or die;
    my ($x,$y);
    if (0) { }
    elsif ($dir8 == 0) { ($x,$y) = ( 0,+1); } # (NT) 
    elsif ($dir8 == 1) { ($x,$y) = (+1,+1); } # NE
    elsif ($dir8 == 2) { ($x,$y) = (+2, 0); } # ET
    elsif ($dir8 == 3) { ($x,$y) = (+1,-1); } # SE
    elsif ($dir8 == 4) { ($x,$y) = ( 0,-1); } # (ST)
    elsif ($dir8 == 5) { ($x,$y) = (-1,-1); } # SW
    elsif ($dir8 == 6) { ($x,$y) = (-2, 0); } # WT
    elsif ($dir8 == 7) { ($x,$y) = (-1,+1); } # NW
    elsif ($dir8 == 8) { ($x,$y) = ( 0, 0); } # (here)
    else { return undef; }
    return ($x,$y);
}

sub formatDFlags {
    my $dflags = shift||0;
    my $ret = "";
    $ret .= "TOS|" if $dflags & D_PKT_FLAG_TO_SERVER;
    $ret .= "FSQ|" if $dflags & D_PKT_FLAG_FIRST_SEQ;
    $ret .= "LSQ|" if $dflags & D_PKT_FLAG_LAST_SEQ;
    $ret .= "RSQ|" if $dflags & D_PKT_FLAG_RETRY_SEQ;
    $ret .= "RV4|" if $dflags & D_PKT_FLAG_RSV4;
    $ret .= "RV5|" if $dflags & D_PKT_FLAG_RSV5;
    $ret .= "RV6|" if $dflags & D_PKT_FLAG_RSV6;
    $ret .= "RV7|" if $dflags & D_PKT_FLAG_RSV7;
    chop $ret;
    return $ret;
}

1;
