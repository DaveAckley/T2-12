#!/usr/bin/perl -w

use FindBin;
use lib $FindBin::Bin;
use Fcntl;
use Errno qw(EAGAIN);

my $pktdev = "/dev/itc/packets";
my $mode = O_RDWR;
my @args = ("-nb",
            "\x81GO1NE girl grill chief complaintive been w2orking on the rr all the live long day",
            "\x82GO2ET phone home run down town bus run all night long doo dah doo dah dit dit dit dah",
            "\x83GO3SE spot run down home base belong to us three us four us five cents a dance",
            "\x85GO5SW atting flies firing the odd shot here and there at the fair get some flare doo dah",
            "\x86GO6WTabix white bread and call it wheat but society survives the apocalypto carribean",
            "\x87GO7NW passage rosemary thyme bomb thumb bluze brothers mothers of invention pretension");
if (scalar(@args)) {
    if ($args[0] eq "-nb") {
        shift @args;
        $mode |= O_NONBLOCK;
    }
}
my $gots = 0;
@args = (@args, @args);
use Time::HiRes;
print "start\n";
my $start = Time::HiRes::time();
sysopen(PKTS, $pktdev, $mode) or die "Can't open $pktdev: $!";
my $pkt;
my $count;
while (scalar(@args)) {
    my $pkt = shift @args;
    my $len = syswrite(PKTS, $pkt);
#    sleep 0.1;
    # while (defined($count = sysread(PKTS, $pkt, 512))) {
    #     last if $count == 0;
    #     print "I GOT($count)='$pkt'\n";
    # }
}
while (defined($count = sysread(PKTS, $pkt, 512))) {
    last if $count == 0;
    print ++$gots.":GOT($count)='$pkt'\n";
}
my $stop = Time::HiRes::time();
sleep .25;
while (defined($count = sysread(PKTS, $pkt, 512))) {
    last if $count == 0;
    print ++$gots."FINAL GOTS($count)='$pkt'\n";
}
die "Error: $!" unless defined($count) or ($mode & O_NONBLOCK) and $!{EAGAIN};
close(PKTS) or die "Can't close $pktdev: $!";
printf("elapsed %f sec\n", $stop-$start);
