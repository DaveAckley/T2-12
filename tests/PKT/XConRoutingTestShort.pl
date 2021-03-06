#!/usr/bin/perl -w

use FindBin;
use lib $FindBin::Bin;
use Fcntl;
use Errno qw(EAGAIN);
use List::Util qw(shuffle);

my $expandos = scalar(@ARGV);
    
my $pktdev = "/dev/itc/packets";
my $mode = O_RDWR;
my $tag = scalar(localtime());
my @args = ("-nb",
            "\x81${tag}GO1NE girl grill chief complaintive been w2orking on the rr all the  \x01\xff\xff\xfe",
            "\x83${tag}GO3SE spot run down home base belong to us three us four us 5% dance \x07\xff\xff\xf8",
            "\x85${tag}GO5SW atting flies firing the odd shot here and there at the flare d \x1f\xff\xff\xf0",
            "\x86${tag}GO6WTabix white bread and call it wheat but society survives apocaly \x3f\xff\xff\xe0",
            "\x87${tag}GO7NW passage rosemary thyme bomb thumb bluze brothers mothers of in \x7f\xff\xff\xc0",
            "\x82${tag}GO2ET phone home run down town bus run all night long doo dah doo da \x03\xff\xff\xfc",   
);
my %rcvcount;
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
my @sndstoppers = ("\x81${tag}END\x81",   "\x82${tag}END\x82",   "\x83${tag}END\x83", 
                   "\x85${tag}END\x85",   "\x86${tag}END\x86",   "\x87${tag}END\x87");
my %rcvstoppers = ("\x85${tag}END\x81"=>1,"\x86${tag}END\x82"=>1,"\x87${tag}END\x83"=>1,
                   "\x81${tag}END\x85"=>1,"\x82${tag}END\x86"=>1,"\x83${tag}END\x87"=>1);
@args = (@args, @sndstoppers);
@args = shuffle @args;
use Time::HiRes;
sysopen(PKTS, $pktdev, $mode) or die "Can't open $pktdev: $!";
printf("Discarded %d packets\n",processAvailablePackets(1));
print "start $tag\n";
my $start = Time::HiRes::time();
my $pkt;
my $count;
my $bytessent = 0;
my $bytesrcvd = 0;
my $pktssent = 0;
my $pktsrcvd = 0;
my $pkterror = 0;
my $pktoverrun = 0;
while (scalar(@args)) {
    my $pkt = rand() > 0.5 ? shift @args : pop @args;
    my $len = syswrite(PKTS, $pkt);
    die "Error: $!" unless defined($len) or ($mode & O_NONBLOCK) and $!{EAGAIN};
    $pktssent++;
    $bytessent += $len;
    processAvailablePackets();
}
my $loops = 0;
while (scalar(keys %rcvstoppers) || $pktsrcvd+$pkterror+$pktoverrun < $pktssent) {
    processAvailablePackets();
    Time::HiRes::usleep(100*++$loops);
    last if $loops >= 1000;
}
my $stop = Time::HiRes::time();
die "Error: $!" unless defined($count) or ($mode & O_NONBLOCK) and $!{EAGAIN};
close(PKTS) or die "Can't close $pktdev: $!";
my @rares = sort { if ($rcvcount{$a} != $rcvcount{$b}) { $rcvcount{$a} <=> $rcvcount{$b} } else { $a cmp $b } } keys %rcvcount;
for my $ky (@rares) {
    printf("%5d '%s'\n",$rcvcount{$ky}, $ky);
}

my $sec = $stop-$start;
my $pct = 100.0*$bytesrcvd/$bytessent;
my $Bps = $bytessent/$sec;
my $KBps = $Bps/1000.0;
my $bps = $Bps*8;
my $Mbps = $bps/1000000.0;
printf("sent %d rcvd %d %3.0f%% err %d ovr %d lost %d elapsed %f sec; sent %d bytes; %5.2f KBps, %5.3f Mbps\n",
       $pktssent, $pktsrcvd,
       $pct,
       $pkterror, $pktoverrun,
       $pktssent-$pktsrcvd,
       $sec, $bytessent, $KBps, $Mbps);

sub processAvailablePackets {
    my $drainOnly = shift;
    my $count;
    my $handled = 0;
    while (defined($count = sysread(PKTS, $pkt, 512))) {
        last if $count == 0;
        ++$handled;
        next if defined $drainOnly;
        my $type = ord(substr($pkt,0,1));
        if ($type & 0x10) {
            ++$pktoverrun;
        } elsif ($type & 0x08) {
            ++$pkterror;
        } else {
            ++$rcvcount{$pkt};
            $bytesrcvd += $count;
            $pktsrcvd++;
            delete $rcvstoppers{$pkt};
        }
    }
    return $handled;
}
