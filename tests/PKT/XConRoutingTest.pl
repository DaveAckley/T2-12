#!/usr/bin/perl -w

use FindBin;
use lib $FindBin::Bin;
use Fcntl;
use Errno qw(EAGAIN);

my $expandos = scalar(@ARGV);
    
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
for (my $i = 0; $i < $expandos; ++$i) {
    @args = (@args, @args);
}
my @sndstoppers = ("\x81END\x81",   "\x82END\x82",   "\x83END\x83",   "\x85END\x85",   "\x86END\x86",   "\x87END\x87");
my %rcvstoppers = ("\x85END\x81"=>1,"\x86END\x82"=>1,"\x87END\x83"=>1,"\x81END\x85"=>1,"\x82END\x86"=>1,"\x83END\x87"=>1);
@args = (@args, @sndstoppers);
use Time::HiRes;
print "start\n";
my $start = Time::HiRes::time();
sysopen(PKTS, $pktdev, $mode) or die "Can't open $pktdev: $!";
my $pkt;
my $count;
my $bytessent = 0;
my $bytesrcvd = 0;
while (scalar(@args)) {
    my $pkt = shift @args;
    my $len = syswrite(PKTS, $pkt);
    $bytessent += $len;
    while (defined($count = sysread(PKTS, $pkt, 512))) {
        last if $count == 0;
        $bytesrcvd += $count;
        delete $rcvstoppers{$pkt};
    }
}
while (scalar(keys %rcvstoppers)) {
    while (defined($count = sysread(PKTS, $pkt, 512))) {
        last if $count == 0;
        $bytesrcvd += $count;
        delete $rcvstoppers{$pkt};
    }
#    Time::HiRes::usleep(10);
}
my $stop = Time::HiRes::time();
die "Error: $!" unless defined($count) or ($mode & O_NONBLOCK) and $!{EAGAIN};
close(PKTS) or die "Can't close $pktdev: $!";
my $sec = $stop-$start;
my $pct = 100.0*$bytesrcvd/$bytessent;
my $Bps = $bytessent/$sec;
my $KBps = $Bps/1000.0;
my $bps = $Bps*8;
my $Mbps = $bps/1000000.0;
printf("rcvd %3.0f%% elapsed %f sec; sent %d bytes; %5.2f KBps, %5.3f Mbps\n",
       $pct,
       $sec, $bytessent, $KBps, $Mbps);
