#!/usr/bin/perl -w

use FindBin;
use lib $FindBin::Bin;

use Time::HiRes ('sleep');

use T2tils;

my $t2 = T2tils::new();

sub togglePinValue {
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
	$val = 1-$val;
	setPinValue($itcdir,$pn,$val);
    }
}


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


sub testSingleITCPair {
    my ($itc1,$itc2) = @_;
    die "finish me ($itc1,$itc2)";
}

sub testConnectedITCs {
    my ($itc1,$itc2) = @_;
    my @allitcs = $t2->getITCDirNames();
    my @itc1s;
    if ($itc1 eq "") {
	@itc1s = @allitcs;
	if ($itc2 ne "") {
	    die "invalid argument $itc2";
	}
    } else {
	@itc1s = $itc1;
    }

    foreach my $i1 (@itc1s) {
	if ($itc2 eq "") {
	    $itc2 = $t2->getOppositeITCDir($i1);
	}
	testSingleITCPair($i1,$itc2);
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
    print "${itcdir}_$pn:$v\n";
}

sub processCmd {
    my $cmd = shift;
    my $orig = $cmd;
    if ($cmd =~ s/^(t)//) {
	my $itc1 = "";
	my $itc2 = "";
	$itc1 = $1 if $cmd =~ s/^(ET|SE|SW|WT|NW|NE)//;
	$itc2 = $1 if $cmd =~ s/^(ET|SE|SW|WT|NW|NE)//;
	if ($cmd !~ s/^$//) {
	    die "Junk '$cmd' at end of command '$orig'"; 
	}
	testConnectedITCs($itc1,$itc2);
	return;
    }
    if ($cmd =~ s/^([dD])([0-9]*)$//) {
	my $up = $1 eq "D";
	my $sleeptenths = $2;
	$sleeptenths = 1 if $sleeptenths eq "";
	if ($up) { $sleeptenths *= 10; } else { $sleeptenths /= 100; }
	my $secs = $sleeptenths/10.0;
	print "delay $secs secs";
	flush STDOUT;
	sleep($secs);
	print "\n";
	return;
    }
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
    } elsif ($cmd =~ s/^[~]$//) {
	togglePinValue($dir,$pn);
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
    my @etpins = $t2->getITCPINs($itc);
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

