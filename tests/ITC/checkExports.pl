#!/usr/bin/perl -w
my @groupStems = (
    "ET_ITC", "SE_ITC", "SW_ITC", "WT_ITC", "NW_ITC", "NE_ITC", 
    "spi_display"
    );

my %pinToGPIO = (
     8 =>  22,
     9 =>  23,
    10 =>  26,
    11 =>  27,
    12 =>  44,
    13 =>  45,
    14 =>  46,
    15 =>  47,
    16 =>  48,
    17 =>  49,
    18 =>  50,
    19 =>  51,
    28 =>  30,
    29 =>  31,
    30 =>  60,
    31 =>  61,
    35 =>  65,
    36 =>  66,
    37 =>  67,
    38 =>  68,
    39 =>  69,
    40 =>  70,
    41 =>  71,
    42 =>  72,
    43 =>  73,
    44 =>  74,
    45 =>  75,
    46 =>  76,
    47 =>  77,
    48 =>  78,
    49 =>  79,
    50 =>  80,
    51 =>  81,
    52 =>   8,
    53 =>   9,
    54 =>  10,
    55 =>  11,
    56 =>  86,
    57 =>  87,
    58 =>  88,
    59 =>  89,
    84 =>   2,
    85 =>   3,
    86 =>   4,
    87 =>   5,
    89 =>   7,
    94 =>  12,
    95 =>  13,
    96 =>  14,
    97 =>  15,
   100 => 110,
   101 => 111,
   102 => 112,
   103 => 113,
   104 => 114,
   105 => 115,
   106 => 116,
   107 => 117,
   109 =>  20,
    );

sub getGPIONumFromPINNum {
    my $linux = shift;
    my $gpio = $pinToGPIO{$linux};
    defined $gpio or die "No GPIO for '$linux'";
    return $gpio;
}

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
    my ($linuxpin,$group) = @_;
    my $gpio = getGPIONumFromPINNum($linuxpin);
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
    my $gpio = getGPIONumFromPINNum($linuxpin);
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

