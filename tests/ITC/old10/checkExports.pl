#!/usr/bin/perl -w

use FindBin;
use lib $FindBin::Bin;

use T2tils;

my $t2 = T2tils::new();

my @exportOK;
my @exportNO;

sub tryUnexport {
    my ($linuxpin,$group) = @_;
    my $gpio = $t2->getGPIONumFromPINNum($linuxpin);
    open(E,">","/sys/class/gpio/unexport") or die "open unexport $group $linuxpin [$gpio]: $!";
    print E "$gpio\n";
    if (close(E)) {
	push @exportOK, $linuxpin;
    } else {
	die "couldn't unexport $group/$linuxpin [$gpio]: $!";
    }
}

sub tryExport {
    my ($linuxpin,$group) = @_;
    my $gpio = $t2->getGPIONumFromPINNum($linuxpin);
    open(EXPORTER,">","/sys/class/gpio/export") or die "open export $group $linuxpin [$gpio]: $!";
    print EXPORTER "$gpio\n";
    if (close(EXPORTER)) {
	tryUnexport($linuxpin,$group);
    } else {
	die "close export $group $linuxpin [$gpio]: $!" if $! ne "Device or resource busy";
	push @exportNO, $linuxpin;
    }
}

sub checkGroup {
    my $name = shift;
    my @pins = $t2->getPINsInGroup($name);
    die unless @pins;
    foreach my $pin (@pins) {
	tryExport($pin,$name);
    }
}

sub assessOurPins {
    
    foreach my $n ($t2->getGroupStems()) {
	checkGroup("pinmux_${n}_default_pins");
	checkGroup("pinmux_${n}_all_gpio_pins");
    }
}

assessOurPins();

die "Export NO: ".join(", ",sort { $a <=> $b} @exportNO)."\n"
    if scalar(@exportNO);
print "All T2 pins exportable\n";


