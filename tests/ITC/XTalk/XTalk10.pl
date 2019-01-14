#!/usr/bin/perl -w

use FindBin;
use lib $FindBin::Bin;
use Fcntl;
use Errno qw(EAGAIN);
use Digest::MD5 qw(md5);
use List::Util qw(shuffle);

my $pktdev = "/dev/itc/packets";
my $pktmode = O_RDWR|O_NONBLOCK;
my $lockdev = "/dev/itc/locks";
#my $lockmode = O_WRONLY;
my $lockmode = O_RDWR;
my $oneshot = 0;
my $dontReallyLock = 0;
my $dontEvenTryLocking = 0;

my %argproc = (
    once => sub { $oneshot = 1; },
    nolock => sub { $dontReallyLock = 1; },
    notrylock => sub { $dontEvenTryLocking = 1; },
    packetlen => \&setPacketLengthCommand,
    help => \&usageDie,
);

sub usageDie {
    my $msg = shift;
    print STDERR "Error: $msg\n" if defined $msg;
    print STDERR "Usage: $0 [OPTARGS]\n";
    print STDERR "Arguments:\n";
    foreach my $a (keys %argproc) {
        print "  $a\n";
    }
    exit 1;
}

sub processArgs {
    my @args = @_;
    foreach my $arg (@args) {
        usageDie "Malformed argument '$arg'" unless $arg =~ /^([[:alpha:]]\w*)(.*?)$/;
        my ($key,$rest) = ($1,$2);
        my $proc = $argproc{$key};
        usageDie "Unrecognized argument '$key'" unless defined $proc;
        &$proc($key,$rest);
    }
}

sub initLockDev {
    sysopen(LOCKS, $lockdev, $lockmode) or die "Can't open locks $lockdev: $!";
}

sub initPktDev {
    sysopen(PKTS, $pktdev, $pktmode) or die "Can't open packets $pktdev: $!";
}

my %GLOBAL_STATS = (
    packetsSent => 0,
    bytesSent => 0,
    packetsRcvd => 0,
    bytesRcvd => 0,
    packetsRcvdByStatus => {},
    lockFlashes => 0,
    lockAcquireFails => 0,
    lockReleaseFails => 0,
    );

sub eexit {
    my $code = shift;
    printGlobalStats();
    exit $code;
}

sub printGlobalStats {
    printf("%d packets sent containing %d bytes\n",
           $GLOBAL_STATS{packetsSent},
           $GLOBAL_STATS{bytesSent});
    printf("%d packets rcvd containing %d bytes\n",
           $GLOBAL_STATS{packetsRcvd},
           $GLOBAL_STATS{bytesRcvd});
    foreach my $status (sort keys %{$GLOBAL_STATS{packetsRcvdByStatus}}) {
        printf(" %d packets %s\n",$GLOBAL_STATS{packetsRcvdByStatus}->{$status},$status);
    }
    printf("%d lock flashes, %d failed acquire, %d failed release\n",
           $GLOBAL_STATS{lockFlashes},
           $GLOBAL_STATS{lockAcquireFails},
           $GLOBAL_STATS{lockReleaseFails});
}

sub sendPacket {
    my $pkt = shift;
    my $len;
    while (1) {
        $len = syswrite(PKTS, $pkt);
        last if defined($len);
        next if $!{EAGAIN};
        die "Error: $!";
    }
    $GLOBAL_STATS{packetsSent}++;
    $GLOBAL_STATS{bytesSent} += $len;
#    printf("%d %d\n",$GLOBAL_STATS{packetsSent},$GLOBAL_STATS{bytesSent});
}


sub assertDir6 { die "dir6" unless $_[0] >= 0 && $_[0] < 6 }
sub assertDir8 { die "dir8" unless $_[0] >= 0 && $_[0] < 8 }
sub assertCond7 { die "cond7" unless $_[0] >= 0 && $_[0] < 7 }

sub readLock {
    my $count;
    my $data;
    $count = sysread(LOCKS, $data, 1);
    die unless $count == 1;
    return ord($data);
}

# return 0 on success, 1 on error
sub lockTry {
    my $dir6 = shift;
    assertDir6($dir6);
    my $byte;
    if ($dontReallyLock) {
        $byte = chr(0);
    } else {
        $byte = chr(1<<$dir6); #REAL ONE
    }
    writeLockByte($byte);
    my $state = readLock();
    return $state != ord($byte);
}

# return 0 on success, 1 on error
sub lockFree {
    my $byte = chr(0);
    writeLockByte($byte);
    my $state = readLock();
    return $state != ord($byte);
}

sub writeLockByte {
    return if $dontEvenTryLocking;

    my $byte = shift;
    #printf("s'%s' '%c' o%03o 0x%02x %d\n",$byte, ord($byte), ord($byte), ord($byte), ord($byte));

    my $len = syswrite(LOCKS, $byte);
    die "Error: $!" unless defined($len);
}

sub flashLock {
    my ($dir,$sleep) = @_;
    $sleep ||= 1.5;
    $GLOBAL_STATS{lockFlashes}++;
    my $fails = 0;
    if (lockTry($dir)) {
        ++$fails;
        ++$GLOBAL_STATS{lockAcquireFails};
    }
#    sleep $sleep;
    if (lockFree()) {
        ++$fails;
        ++$GLOBAL_STATS{lockReleaseFails};
    }
    return $fails;
}

sub makeRandomBytes {
    my $len = shift;
    die unless $len > 0 && $len < 256;
    my $data = "";
    for (my $i = 0; $i < $len; ++$i) {
        my $byte = rand(256);
        $data .= chr($byte);
    }
    return $data;
}

# +----------------------+  +-------------------+
# |        dir8          |  |       dir6        |
# |        N=0           |  |                   |
# |  NW=7       NE=1     |  |   NW=4    NE=5    |
# |                      |  |                   |
# |WT=6              ET=2|  |WT=3          ET=0 |
# |                      |  |                   |
# |  SW=5       SE=3     |  |   SW=2    SE=1    |
# |        S=4           |  +-------------------+
# +----------------------+

my @dir8from6 = (2, 3, 5, 6, 7, 1);
my @dir6from8 = (-1, 5, 0, 1, -1, 2, 3, 4);

sub dir6ToDir8 {
    my $dir6 = shift;
    assertDir6($dir6);
    return  $dir8from6[$dir6];
}

sub dir8ToDir6 {
    my $dir8 = shift;
    assertDir8($dir8);
    die unless $dir6from8[$dir8] >= 0;
    return  $dir6from8[$dir8];
}

my $STD_PKT_LEN = 113;
sub setPacketLengthCommand {
    my ($key,$rest) = @_;
    usageDie "packetlen=1..250" unless $rest =~ /=(\d+)$/;
    my $len = $1;
    usageDie "packetlen=1..250" unless $len >= 1 && $len <= 250;
    $STD_PKT_LEN = $len;
    print "Packet length set to $STD_PKT_LEN\n";
}
my $GLOBAL_PKT_COUNTER = 0;
# Info per itc/dir6: {
#   pktCountSent (also tag)
#   lastPktTagRcvd
#   pendingPkt
#   perCondition0..6 [ # condition is flashLock0..5 or no flash 6
#     { sent okay corrupt lost} {sent okay corrupt lost} ..
#   ]
# }

my @pktStats;
sub initPktStats {
    for (my $dir6 = 0; $dir6 < 6; ++$dir6) {
        $pktStats[$dir6] = {};
        $pktStats[$dir6]->{pktCountSent} = 0;
        $pktStats[$dir6]->{pktCountRcvd} = 0;
        $pktStats[$dir6]->{lastPktTagRcvd} = -1;
        $pktStats[$dir6]->{pendingPkt} = undef;
        $pktStats[$dir6]->{pendingCondition} = 6;
        $pktStats[$dir6]->{perCondition} = [];
        for (my $cond7 = 0; $cond7 < 7; ++$cond7) {
            $pktStats[$dir6]->{perCondition}->[$cond7] ={
                sent => 0, okay => 0, corrupt => 0, lost => 0
            }
        }
    }
}

sub printPktStats {
    for (my $dir6 = 0; $dir6 < 6; ++$dir6) {
        printf("Dir %d",$dir6);
        for (my $cond7 = 0; $cond7 < 7; ++$cond7) {
            my ($statref,$condref) = getPktStatsAndCond($dir6,$cond7);
            printf(" %d sent %d rcvd",$statref->{pktCountSent},$statref->{pktCountRcvd}) if $cond7 == 0;
            printf(" c%d %s %s %s %s SKCL",
                   $cond7,
                   $condref->{sent} > 0 ? $condref->{sent} : "_",
                   $condref->{okay} > 0 ? $condref->{okay} : "_",
                   $condref->{corrupt} > 0 ? $condref->{corrupt} : "_",
                   $condref->{lost} > 0 ? $condref->{lost} : "_");
        }
        printf("\n");
    }
}

sub updatePktStatsOutbound {
    my ($pkt,$dir6,$cond7) = @_;
    my ($statref,$condref) = getPktStatsAndCond($dir6,$cond7);
    $statref->{pktCountSent}++;
    $condref->{sent}++;
}

sub updatePktStatsInbound {
    my ($tag,$dir6,$cond7) = @_;
    my ($statref,$condref) = getPktStatsAndCond($dir6,$cond7);
    $statref->{pktCountRcvd}++;
    if ($statref->{lastPktTagRcvd} < 0) {
        $statref->{lastPktTagRcvd} = $tag;
    } elsif ($statref->{lastPktTagRcvd} + 1 < $tag) {
        $condref->{lost} += $tag-($statref->{lastPktTagRcvd} + 1);
    } elsif ($statref->{lastPktTagRcvd} + 1 == $tag) {
        ++$condref->{okay};
    }
    $statref->{lastPktTagRcvd} = $tag;
}

sub checksumString {
    my $string = shift;
    my $hash4 = substr( md5($string), 0, 4 );
    return $hash4;
}

sub getPktStatsAndCond {
    my ($dir6,$cond7) = @_;
    assertDir6($dir6);
    assertCond7($cond7);
    my $statref = $pktStats[$dir6];
    my $condref = $statref->{perCondition}->[$cond7];
    return ($statref,$condref);
}

# return (STATUS, TAG, DIR6, COND7)
# STATUS:
# "OK" - all good, TAG, DIR6, COND7 also returned
# "OVERRUN" - device level packet overrun 
# "ERROR" - device level error
# "CORRUPT" - unanalyzable
# "CHECKSUM" - looked plausible but failed checksum
# "INTERNAL" - impossible

sub analyzeInboundPacket {
    my $packet = shift;
    my $type = ord(substr($packet,0,1));
    if ($type & 0x10) {
        return "OVERRUN";
    } elsif ($type & 0x08) {
        return "ERROR";
    } 

    $packet =~ /^(.)(.+)(....)$/s or return "CORRUPT";
    my ($hdr, $body, $chksum) = ($1, $2, $3);
#    substr($body,10,1) = "X" if (rand(1) < 0.02);
    return "CHECKSUM" if checksumString($body) ne $chksum; # CHECKSUM
#    return "RANGOON"  if (rand(1) < 0.02);
    $body =~ m!^(\d+)/(\d+)\[(\d+)\]! or return "INTERNAL";
    my ($dir6,$cond7,$tag) = ($1,$2,$3);
    return ("OK", $tag, $dir6, $cond7);
}

sub makePacketForDir6UnderCond7 {
    my ($dir6,$cond7) = @_;
    my ($statref,$condref) = getPktStatsAndCond($dir6,$cond7);
    die "pending " if defined $statref->{pendingPkt};
    my $dir8 = dir6ToDir8($dir6);
    my $hdr = chr(0x80+$dir8);
    my $packet = sprintf("%d/%d[%d]",$dir6,$cond7,++$condref->{pktCountSent});
    $packet .= makeRandomBytes($STD_PKT_LEN - length($packet) - 4 - 1);
    $packet .= checksumString($packet);
    $packet = "$hdr$packet";
    return $packet;
}

my @shuffleDir6 = (0,1,2,3,4,5);

sub sendAllUnderCond {
    my $cond7 = shift;
    assertCond7($cond7);
    @shuffleDir6 = shuffle @shuffleDir6;
    foreach my $dir6 (@shuffleDir6) {
        my $pkt = makePacketForDir6UnderCond7($dir6,$cond7);
        updatePktStatsOutbound($pkt,$dir6,$cond7);
        sendPacket($pkt);
    }
}

my $PKTS_PER_COND = 6;
sub runOneCond {
    my $cond7 = shift;
    assertCond7($cond7);
    for (my $i = 0; $i < $PKTS_PER_COND; ++$i) {
        sendAllUnderCond($cond7);
    }
    if ($cond7 < 6) { # 0..5 are actual locking attempts
        my $wait = rand(0.1);
#        sleep $wait;
        flashLock($cond7,$wait);    
    }
    do {
        sleep 0.1;
    } while (processAvailablePackets() > 0);
}

sub processAvailablePackets {
    my $drainOnly = shift;
    my $handled = 0;
    my $count;
    while (defined($count = sysread(PKTS, $pkt, 512))) {
        last if $count == 0;
        ++$handled;
        next if defined $drainOnly;
        ++$GLOBAL_STATS{packetsRcvd};
        $GLOBAL_STATS{bytesRcvd} += $count;
        
        my ($status, $tag, $dir6, $cond7) = analyzeInboundPacket($pkt);
        ++$GLOBAL_STATS{packetsRcvdByStatus}->{$status};
        if ($status eq "OK") {
            ++$GLOBAL_STATS{packetsRcvdStatusOK};
            updatePktStatsInbound($tag,$dir6,$cond7);
        } else {
            printf("GOGON(%s)\n",$status);
        }
    }
    return $handled;
}


sub main {
    processArgs(@ARGV);
    initLockDev();
    initPktDev();
    initPktStats();
    my $drain = processAvailablePackets(1); # Drain any pending packets
    while (1) {
    printf("Discarded %d prior packets\n",$drain);
    for (my $loops = 0; $loops < 4; ++$loops) {
        for (my $cond7 = 0; $cond7 < 7; ++$cond7) {
            runOneCond($cond7);
        }
    }
    sleep 1;
    processAvailablePackets(); # One last chance
    printPktStats();
    $drain = processAvailablePackets(1); # Check again
    printf("%d late packets\n",$drain);
    printGlobalStats();
    last if $oneshot;
    sleep 1;
    printf("Going again\n");
    }
}

main();
exit 0;
