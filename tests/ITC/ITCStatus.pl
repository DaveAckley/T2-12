#!/usr/bin/perl -w

use FindBin;
use lib $FindBin::Bin;

use T2tils;

my $t2 = T2tils::new();

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

my @dirs = @ARGV;
@dirs = $t2->getITCDirNames() unless scalar(@dirs);
my @itcnames = $t2->getITCAbbrs();
print "    ".join(" ",@itcnames)."\n";
foreach my $dir (@dirs) {
    reportITC($dir);
}

exit;

