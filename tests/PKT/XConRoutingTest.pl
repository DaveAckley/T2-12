#!/usr/bin/perl -w

use FindBin;
use lib $FindBin::Bin;
use Fcntl;
use Errno qw(EAGAIN);

my $pktdev = "/dev/itc/packets";
my $mode = O_RDWR;
if (scalar(@ARGV)) {
    if ($ARGV[0] eq "-nb") {
        shift @ARGV;
        $mode |= O_NONBLOCK;
    }
}
sysopen(PKTS, $pktdev, $mode) or die "Can't open $pktdev: $!";
my $pkt;
my $count;
while (scalar(@ARGV)) {
    my $pkt = shift @ARGV;
    my $len = syswrite(PKTS, $pkt);
    while (defined($count = sysread(PKTS, $pkt, 512))) {
        last if $count == 0;
        print "I GOT($count)='$pkt'\n";
    }
}
while (defined($count = sysread(PKTS, $pkt, 512))) {
    last if $count == 0;
    print "I GOT($count)='$pkt'\n";
}
sleep 1.5;
while (defined($count = sysread(PKTS, $pkt, 512))) {
    last if $count == 0;
    print "FINAL GOTS($count)='$pkt'\n";
}
die "Error: $!" unless defined($count) or ($mode & O_NONBLOCK) and $!{EAGAIN};
close(PKTS) or die "Can't close $pktdev: $!";
