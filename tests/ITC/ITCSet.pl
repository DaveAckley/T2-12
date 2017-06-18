#!/usr/bin/perl -w

use FindBin;
use lib $FindBin::Bin;

use T2tils;

my $t2 = T2tils::new();

sub reportPinValue {
    my ($itcdir,$pn) = @_;
    my @pins;
    if ($pn eq "") {
	@pins = $t2->getITCAbbrs();
    } else {
	push @pins, $pn;
    }
    foreach my $p (@pins) {
	my $PIN = $t2->getPINFromITCAbbr($itcdir,$p);
	die unless defined $PIN;
	my $val = $t2->getPINValue($PIN);
	print "${itcdir}_$p=$val\n";
    }
}

sub reportPinInfo {
    my ($itcdir,$pn) = @_;
    my @pins;
    if ($pn eq "") {
	@pins = $t2->getITCAbbrs();
    } else {
	push @pins, $pn;
    }
    foreach my $p (@pins) {
	my $PIN = $t2->getPINFromITCAbbr($itcdir,$p);
	die unless defined $PIN;
	my $gpio = $t2->getGPIONumFromPINNum($PIN);
	my $val = $t2->getPINInfo($PIN);
	print "${itcdir}_$p=$val (PIN=$PIN; gpio=$gpio)\n";
    }
}

sub initPin {
    my ($itcdir,$pn) = @_;
    my @pins;
    if ($pn eq "") {
	@pins = $t2->getITCAbbrs();
    } else {
	push @pins, $pn;
    }
    foreach my $p (@pins) {
	my $PIN = $t2->getPINFromITCAbbr($itcdir,$p);
	die unless defined $PIN;
	my $dir = $t2->getIODirFromAbbr($p);
	$t2->setPINDirection($PIN,$dir);
	reportPinInfo($itcdir,$p);
    }
}

sub setPinValue {
    my ($itcdir,$pn,$val) = @_;
    my $PIN = $t2->getPINFromITCAbbr($itcdir,$pn);
    die unless defined $PIN;
    $t2->setPINValue($PIN,$val);
    my $v = $t2->getPINValue($PIN);
    print "${itcdir}_$pn:$val\n";
}

sub setPinDirection {
    my ($itcdir,$pn,$dir) = @_;
    my $PIN = $t2->getPINFromITCAbbr($itcdir,$pn);
    die unless defined $PIN;
    $t2->setPINDirection($PIN,$dir);
    my $v = $t2->getPINValue($PIN);
    print "${itcdir}_$pn:$val\n";
}

sub processCmd {
    my $cmd = shift;
    if ($cmd !~ s/^(ET|SE|SW|WT|NW|NE)//) {
	die "Unrecognized ITC pin '$cmd'";
    }
    my $dir = $1;
    my $pn = "";
    if ($cmd =~ s/^_?(TR|TD|RR|RD|OQ|OG|IQ|IG)//) {
	$pn = $1;
    }
    if ($cmd =~ s/^$//) {
	reportPinValue($dir,$pn);
    } elsif ($cmd =~ s/^[?]$//) {
	reportPinInfo($dir,$pn);
    } elsif ($cmd =~ s/^[!]$//) {
	initPin($dir,$pn);
    } elsif ($cmd =~ s/^=(0|1)$//) {
	setPinValue($dir,$pn,$1);
    } else {
	die "Unrecognized operation '$cmd'";
    }
}
sub reportITC {
    my $dir = shift;
    die "No such ITC dir '$dir'"
	unless defined $t2->getITCDirIndex($dir);
    my $itc = "${dir}_ITC";
    my @etpins = $t2->getITCPins($itc);
    print "$dir  ";
    foreach my $etp (@etpins) {
	my $v = $t2->getPINValue($etp);
	print " $v ";
    }
    print "\n";
}

foreach my $cmd (@ARGV) {
    processCmd($cmd);
}

exit;

