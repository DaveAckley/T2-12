#!/usr/bin/perl -w
my @groupStems = (
    "ET_ITC", "SE_ITC", "SW_ITC", "WT_ITC", "NW_ITC", "NE_ITC", 
    "spi_display"
    );

open(PINGROUPS,"<", "/sys/kernel/debug/pinctrl/44e10800.pinmux/pingroups") or die "$!";
my $curgp;
my %groups;
my $hdr = <PINGROUPS>;
die unless $hdr eq "registered pin groups:\n";
while (<PINGROUPS>) {
    chomp;
    if (/^group: ([^ ]+)( |$)/) {
	$curgp = $1;
	next;
    }
    if (/^pin ([0-9]+) \(([0-9a-f.]+)\)( |$)/) {
	my ($pin,$addr) = ($1,$2);
	die unless $curgp;
	push @{$groups{$curgp}}, $pin;
	next;
    }
    if (/^ *$/) {
	next;
    }
    die "Unrecognized: '$_'\n";
}
close(PINGROUPS) or die "$!";

# foreach my $g (sort keys %groups) {
#     print "$g: ".join(", ",@{$groups{$g}})."\n";
# }


my @exportOK;
my @exportNO;

sub tryUnexport {
    my ($pin,$group) = @_;
    open(E,">","/sys/class/gpio/unexport") or die "open unexport $group $pin: $!";
    print E "$pin\n";
    if (close(E)) {
	push @exportOK, $pin;
    } else {
	die "couldn't unexport $group/$pin: $!";
    }
}

sub tryExport {
    my ($pin,$group) = @_;
    open(EXPORTER,">","/sys/class/gpio/export") or die "open export $group $pin: $!";
    print EXPORTER "$pin\n";
    if (close(EXPORTER)) {
	tryUnexport($pin,$group);
    } else {
	push @exportNO, $pin
    }
}

sub checkGroup {
    my $name = shift;
    my @pins = @{$groups{$name}};
    die unless @pins;
    foreach my $pin (@pins) {
	tryExport($pin,$name);
    }
}

sub assessOurPins {
    
    foreach my $n (@groupStems) {
	checkGroup("pinmux_${n}_default_pins");
	checkGroup("pinmux_${n}_all_gpio_pins");
    }
}

assessOurPins();
print "Export OK: ".join(", ",sort { $a <=> $b} @exportOK)."\n";
print "Export NO: ".join(", ",sort { $a <=> $b} @exportNO)."\n";

