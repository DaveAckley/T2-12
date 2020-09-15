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
    lexEncode
    lexDecode

    hexEscape
    deHexEscape

    hack16

    now
    ago
    aged

    formatSeconds
    formatSize
    formatPercent
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
    );
my @processops = qw(
    runCommandWithSync
    );
our @EXPORT_OK = (@math, @dirs, @packet, @fileops, @processops);
our %EXPORT_TAGS = (
    math => \@math,
    dir6s => \@dir6s,
    dir8s => \@dir8s,
    dirs => \@dirs,
    packet => \@packet,
    fileops => \@fileops,
    processops => \@processops,
    all => \@EXPORT_OK
    );

## IMPORTS
use List::Util qw(shuffle);
use Digest::SHA qw(sha512_hex);
use Time::HiRes qw(time);
    
use DP qw(:all);

## MATH

sub ceiling {
    my $n = shift;
    return ($n == int $n) ? $n : int($n + 1);
}

sub max {
    my ($n,$m) = @_;
    return ($n >= $m) ? $n : $m;
}

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

sub formatSeconds {
    my $sec = shift;
    my $neg = "";
    my $ret = "";
    if ($sec < 0) {
        $neg = "-";
        $sec = -$sec;
    }
    for my $size (@chunks) {
        if ($sec > $size) {
            my $count = int($sec/$size);
            $sec -= $count*$size;
            $ret .= " " if $ret ne "";
            $ret .= "${count}$units{$size}";
        }
    }
    return "$neg$ret";
}

my @kunits = split(//," KMGTPE");
sub formatSize {
    my $size = shift;
    my $ret = "";
    return " <0 " if $size < 0;
    for my $unit (@kunits) {
        if ($size < 1000) {
            if ($size < 1) {
                $ret = sprintf(".%02d%s",int($size*100),$unit);
            } elsif ($size > 10 || int($size) == $size) {
                $ret = sprintf("%3d%s", $size,$unit);
            } else {
                $ret = sprintf("%3.1f%s",$size,$unit);
            }
            last;
        }
        $size /= 1000.0;
    }
    return $ret;
}

sub formatPercent {
    my $pct = shift;
    return " <0%" if $pct < 0;
    return sprintf(".%02d%%",int($pct*100)) if $pct < 1;
    return sprintf("%3.1f%%",$pct) if $pct < 10;
    return sprintf("%3d%%",int($pct)) if $pct < 999;
    return "1K+%";
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


1;
