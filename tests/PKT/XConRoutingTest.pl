#!/usr/bin/perl -w

use FindBin;
use lib $FindBin::Bin;
use Fcntl;
use Errno qw(EAGAIN);

my $expandos = scalar(@ARGV);
    
my $pktdev = "/dev/itc/packets";
my $mode = O_RDWR;
my $tag = scalar(localtime());
my @args = ("-nb",
            "\x81${tag}GO1NE girl grill chief complaintive been w2orking on the rr all the live long \x01\xff\xff\xfe",
            "\x83${tag}GO3SE spot run down home base belong to us three us four us 5% dance \x07\xff\xff\xf8",
            "\x85${tag}GO5SW atting flies firing the odd shot here and there at the flare doo dah \x1f\xff\xff\xf0",
            "\x86${tag}GO6WTabix white bread and call it wheat but society survives the apocalypto \x3f\xff\xff\xe0",
            "\x87${tag}GO7NW passage rosemary thyme bomb thumb bluze brothers motherssage rosemary thyme bomb thumb bluze brothers motherssage rosemary thyme bomb thumb bluze brothers mothers of pretension \x7f\xff\xff\xc0",
            "\x82${tag}GO2ET phone home run down town bus run all night long doo dah doo dah  dit dah \x03\xff\xff\xfc",   
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
for (my $i = 0; $i < scalar(@args); ++$i) {
    $args[$i] .= $i;
}
my @sndstoppers = ("\201${tag}END\201",   "\202${tag}END\202",   "\203${tag}END\203", 
                   "\205${tag}END\205",   "\206${tag}END\206",   "\207${tag}END\207");
my %rcvstoppers = ("\205${tag}END\201"=>1,"\206${tag}END\202"=>1,"\207${tag}END\203"=>1,
                   "\201${tag}END\205"=>1,"\202${tag}END\206"=>1,"\203${tag}END\207"=>1);
#print join("--\n",keys  %rcvstoppers);
@args = (@args, @sndstoppers);
use Time::HiRes;
print "start $tag\n";
my $start = Time::HiRes::time();
sysopen(PKTS, $pktdev, $mode) or die "Can't open $pktdev: $!";
my $pkt;
my $count;
my $bytessent = 0;
my $bytesrcvd = 0;
my $pktssent = 0;
my $pktsrcvd = 0;
my $pkterror = 0;
my $pktoverrun = 0;
my %allunrcvd;
while (scalar(@args)) {
    my $pkt = rand() > 0.5 ? shift @args : pop @args;
    my $len;
    while (1) {
        processAvailablePackets();
        $len = syswrite(PKTS, $pkt);
        last if defined($len);
        next if ($mode & O_NONBLOCK) and $!{EAGAIN};
        die "Error: $!";
    }
    ++$allunrcvd{substr($pkt,1)};
    $pktssent++;
    $bytessent += $len;
#    print "O$pktssent $pkt O$pktssent\n";
}
my $loops = 0;
while (scalar(keys %rcvstoppers) || $pktsrcvd+$pkterror+$pktoverrun < $pktssent) {
#    print "SK=".scalar(keys %rcvstoppers)." $pktsrcvd+$pkterror+$pktoverrun < $pktssent\n";
    processAvailablePackets();
    Time::HiRes::usleep(100*++$loops);
    last if $loops >= 250;
}
my $stop = Time::HiRes::time();
die "Error: $!" unless defined($count) or ($mode & O_NONBLOCK) and $!{EAGAIN};
close(PKTS) or die "Can't close $pktdev: $!";
my @rares = sort { if ($rcvcount{$a} != $rcvcount{$b}) { $rcvcount{$a} <=> $rcvcount{$b} } else { $a cmp $b } } keys %rcvcount;
# for my $ky (@rares) {
#     printf("%5d '%s'\n",$rcvcount{$ky}, $ky);
# }

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
for my $p (sort keys %allunrcvd) {
    my $v = $allunrcvd{$p};
    print "$v $p\n" if defined($v) && $v != 0;
}

sub processAvailablePackets {
    my $count;
    while (defined($count = sysread(PKTS, $pkt, 512))) {
        last if $count == 0;
        my $type = ord(substr($pkt,0,1));
        if ($type & 0x10) {
            ++$pktoverrun;
        } elsif ($type & 0x08) {
            ++$pkterror;
        } else {
            print "HUH? ($pkt)\n" unless defined $allunrcvd{substr($pkt,1)};
            --$allunrcvd{substr($pkt,1)};
            ++$rcvcount{$pkt};
            $bytesrcvd += $count;
            $pktsrcvd++;
#            print "I$pktsrcvd $pkt I$pktsrcvd\n";
            delete $rcvstoppers{$pkt};
        }
    }
}
