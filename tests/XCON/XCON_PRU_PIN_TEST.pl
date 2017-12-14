#!/usr/bin/perl -w

use FindBin;
use lib $FindBin::Bin;

my %ITCDirs = (
    ET => 0,
    SE => 1,
    SW => 2,
    WT => 3,
    NW => 4,
    NE => 5
    );

my @ITCDirsByIndex = sort { $ITCDirs{$a} <=> $ITCDirs{$b} } keys %ITCDirs;
my @PRUOut = ('TXRDY', 'TXDAT');
my @PRUIn = ('RXRDY', 'RXDAT');

sub oppositeFace {
    my $dir = shift;
    my $idx = $ITCDirs{$dir};
    die unless defined $idx;
    my $oppidx = ($idx+3)%6;
    return $ITCDirsByIndex[$oppidx];
}

sub setPin {
    my ($pin,$val) = @_;
    `echo $val > /sys/class/itc_pkt/$pin`;
}

sub getPin {
    my ($pin) = @_;
    my $v = `cat /sys/class/itc_pkt/$pin`;
    return $v;
}

sub clearOutputs {
    foreach my $d (@ITCDirsByIndex) {
        foreach my $p (@PRUOut) {
            my $pin = "${d}_${p}";
            setPin($pin,0);
        }
    }
}

sub reportInputs {
    foreach my $p (@PRUIn) {
        foreach my $d (@ITCDirsByIndex) {
            my $pin = "${d}_${p}";
            my $val = getPin($pin);
            chomp($val);
            print "$pin = $val  ";
        }
        print "\n";
    }
}

clearOutputs();
foreach my $d (@ITCDirsByIndex) {
    foreach my $p (@PRUOut) {
        my $pin = "${d}_${p}";
        print "////TESTING $pin\n";
        setPin($pin,1);
        reportInputs();
        setPin($pin,0);
    }
}

