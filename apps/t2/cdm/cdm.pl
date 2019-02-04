#!/usr/bin/perl -w  # -*- perl -*-
use Fcntl;
use File::Path qw(make_path);
use Errno qw(EAGAIN);
use Time::HiRes;
use List::Util qw/shuffle/;
use Digest::SHA qw(sha512_hex);

my $CDM_PKT_TYPE = 0x03;
my $CDM_PKT_TYPE_BYTE = chr($CDM_PKT_TYPE);

my $pktdev = "/dev/itc/packets";
my $mode = O_RDWR|O_NONBLOCK;

my @dirnames = ("NT", "NE", "ET", "SE", "ST", "SW", "WT", "NW");

sub getDirName {
    my $dir = shift;
    die unless defined $dir;
    return $dirnames[$dir] if defined $dirnames[$dir];
    return "Bad dir '$dir'";
}

sub openPackets {
    sysopen(PKTS, $pktdev, $mode) or die "Can't open $pktdev: $!";
}

sub readPacket {
    my $pkt;
    my $count;
    if (defined($count = sysread(PKTS, $pkt, 512))) {
        return if $count == 0;
        print "GOT PACKET($pkt)\n";
        return $pkt;
    }
    return undef;
}
        

sub writePacket {
    my $pkt = shift;
    while (1) {
        my $len = syswrite(PKTS, $pkt);
        return if defined $len;
        die "Error: $!" unless $!{EAGAIN};
        print "BLOCKING\n";
        Time::HiRes::usleep(100);
    }
}

sub closePackets {
    close(PKTS) or die "Can't close $pktdev: $!";
}

my $baseDir = "/data";
my @subDirs = ("archive", "common", "pending", "unique");
my $commonDir = "$baseDir/common";

sub checkInitDir {
    my $dir = shift;
    if (-d $dir) {
        print "Found $dir\n";
        return 1;
    }
    if (-e $dir) {
        print "$dir exists but is not a directory\n";
        return 0;
    }
    if (make_path($dir)) {
        print "Made $dir\n";
        return 1;
    }
    return 0;
}
sub checkInitDirs {

    foreach my $sub (@subDirs) {
        my $path = "$baseDir/$sub";
        if (!checkInitDir "$path") {
            die "Problem with '$path'";
        }
    }
}

sub loadMFZ {
    my $path = shift;
    print "loadMFZ $path\n";
}

sub loadMFZs {
    my $dir = shift;
    opendir DIR, $dir or die "Can't open $dir: $!";
    while (my $entry = readdir DIR) {
        my $path = "$dir/$entry";
        if ($entry =~ /[.]mfz$/) {
            loadMFZ($path);
        }
    }
    closedir DIR or die "Can't close $dir: $!";
}

sub sendCDMTo {
    my ($dest, $type, $args) = @_;
    die if $dest < 1 or $dest > 7 or $dest == 4;
    die if length($type) != 1;
    my $pkt = chr(0x80+$dest).chr($CDM_PKT_TYPE).$type;
    $pkt .= $args if defined $args;
    print "SENDIT($pkt)\n";
    writePacket($pkt);
}

sub randDir {
    my $dir = int(rand(6)) + 1;
    $dir += 1 if $dir > 3;
    return $dir; # 1,2,3,5,6,7
}

my %dataModel;
my @pendingPaths;
my %hoodModel;

sub loadCommonFiles {
    if (!opendir(COMMON, $commonDir)) {
        print "WARNING: Can't load $commonDir: $!\n";
        return;
    }
    @pendingPaths = shuffle readdir COMMON;
    closedir COMMON or die "Can't close $commonDir: $!\n";
}

my $digester = Digest::SHA->new(256);

sub checksumWholeFile {
    my $path = shift;
    $digester->reset();
    $digester->addfile($path);
    my $cs = $digester->b64digest();
    print " $path => $cs\n";
    return $cs;
}

sub checkCommonFile {
    if (scalar(@pendingPaths) == 0) {
        loadCommonFiles();
        return;
    }
    my $filename = shift @pendingPaths;
    return unless defined $filename && $filename =~ /[.]mfz$/;

    my $path = "$commonDir/$filename";
    print "CHECKING $path\n";
    my $finfo = getFinfo($path);

    # Need checksum?
    if (!defined $finfo->{checksum}) {
        $finfo->{checksum} = checksumWholeFile($path);
        return; # That's enough for now..
    }


}

sub newFinfo {
    my $path = shift;
    die unless defined $path && -r $path;
    return {
        path => $path,
        length => -s _,
        modtime => -M _,
        checksum => undef,
        signingHandle => undef,
        innerTimestamp => undef
    };
}

sub getFinfo {
    my $path = shift;
    my $finfo;
    while (!defined($finfo = $dataModel{$path})) {
        $dataModel{$path} = newFinfo($path);
    }
    return $finfo;
}


sub newNgb {
    my $dir = shift;
    my $longAgo = 1000000;
    die unless defined $dir;
    return {
        dir => $dir,
        clacksSinceAliveSent => $longAgo,
        clacksSinceAliveRcvd => $longAgo,
        isAlive => 0,
    };
}

sub printHash {
    my $href = shift;
    foreach my $key (sort keys %{$href}) {
        my $v = $href->{$key};
        print " $key ".($v ? $v : "undef")."\n";
    }
}

sub getNgbInDir {
    my $dir = shift;
    my $ngb;
    while (!defined($ngb = $hoodModel{$dir})) {
        $hoodModel{$dir} = newNgb($dir);
    }
    return $ngb;
}

sub oddsOf {
    my ($this, $outof) = @_;
    return rand($outof) < $this;
}

sub oneIn {
    return oddsOf(1, shift);
}

sub getRandomNgb {
    return getNgbInDir(randDir());
}

sub getRandomAliveNgb {
    my $ngb;
    my $count = 0;
    foreach my $k (keys %hoodModel) {
        my $v = $hoodModel{$k};
        $ngb = $v if $v->{isAlive} && oneIn(++$count);
    }
    return $ngb; # undef if none alive
}

my $continueEventLoop = 1;
sub doBackgroundWork {

    # ALIVENESS MGMT
    my $ngb = getRandomNgb();
#    print getDirName($ngb->{dir})." alive ".$ngb->{isAlive}." clacks ".$ngb->{clacksSinceAliveRcvd}."\n";
    if ($ngb->{isAlive} && rand(++$ngb->{clacksSinceAliveRcvd}) > 20) {
        $ngb->{isAlive} = 0;
        print getDirName($ngb->{dir})." is dead\n";
    }
    
    if (rand(++$ngb->{clacksSinceAliveSent}) > 10) {
        $ngb->{clacksSinceAliveSent} = 0;
        sendCDMTo($ngb->{dir},'A');
    }

    # COMMON MGMT
    checkCommonFile();
}

sub processPacket {
    my $pkt = shift;
    if (length($pkt) < 3) {
        print "Short packet '$pkt' ignored\n";
        return;
    }
    my @bytes = split(//,$pkt);
    my $srcDir = ord($bytes[0])&0x07;
    if ($bytes[1] eq $CDM_PKT_TYPE_BYTE) {
        if ($bytes[2] eq "A") {
            my $ngb = getNgbInDir($srcDir);
            $ngb->{clacksSinceAliveRcvd} = 0;
            if (!$ngb->{isAlive}) {
                $ngb->{isAlive} = 1;
                print getDirName($srcDir)." is alive\n";
            }
            return;
        }
    }
    print "UNHANDLED PKT($pkt)\n";
}

sub now {
    return time()>>1;
}

sub eventLoop {
    my $lastBack = now();
    my $incru = 10000;
    my $minu = 10000;
    my $maxu = 500000;
    my $usleep = $minu;
    while ($continueEventLoop) {
        if (my $packet = readPacket()) {
            processPacket($packet);
            $usleep = $minu;
            next;
        }
        if ($lastBack != now()) {
            doBackgroundWork();
            $lastBack = now();
            next;
        }
        Time::HiRes::usleep($usleep);
        if ($usleep < $maxu) {
            $usleep += $incru; 
        }
    }
    print "$lastBack time\n";
    loadMFZs($commonDir)
}

sub main {
    checkInitDirs();
    openPackets();
    eventLoop();
    closePackets();
}

main();
exit 9;


