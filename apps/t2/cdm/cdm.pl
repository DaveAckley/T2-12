#!/usr/bin/perl -w  # -*- perl -*-
use Fcntl;
use File::Path qw(make_path);
use Errno qw(EAGAIN);
use Time::HiRes;
use List::Util qw/shuffle/;
use Digest::SHA qw(sha512_hex);
use DateTime::Format::Strptime;

my $CDM_PKT_TYPE = 0x03;
my $CDM_PKT_TYPE_BYTE = chr($CDM_PKT_TYPE);

my $MAX_MFZ_NAME_LENGTH = 28+4; # 4 for '.mfz'

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
    my ($pkt,$ignoreUnreach) = @_;
    while (1) {
        my $len = syswrite(PKTS, $pkt);
        return if defined $len;
        if ($ignoreUnreach && $!{EHOSTUNREACH}) {
            print "Host unreachable, ignored\n";
            return;
        }
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
my $pendingDir = "$baseDir/pending";

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

sub sendCDMTo {
    my ($dest, $type, $args) = @_;
    die if $dest < 1 or $dest > 7 or $dest == 4;
    die if length($type) != 1;
    my $pkt = chr(0x80+$dest).chr($CDM_PKT_TYPE).$type;
    $pkt .= $args if defined $args;
    print "SENDIT($pkt)\n";
    writePacket($pkt,1);
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
    my $cs = substr($digester->digest(),0,16);
    my $hexcs = unpack("H*",$cs);
    print " $path => $hexcs\n";
    return $cs;
}

my $globalCheckedFilesCount = 0;

sub checkMFZDataFor {
    my $finfo = shift;
    return 0 if defined $finfo->{seqno}; # Or some refreshment maybe?

    #### REPLACE THIS WITH 'mfzrun VERIFY' ONCE AVAILABLE
    my $path = $finfo->{path};
    my $cmd = "mfzrun $path list";
    my $output = `$cmd`;
    if ($output !~ s/^SIGNED BY RECOGNIZED HANDLE: (:?[a-zA-Z][-., a-zA-Z0-9]{0,62}) \(//) {
        print "Handle of $path not found in '$output'\n";
        return 0;
    }
    my $handle = $1;
    if ($output !~ s/^\s+MFZPUBKEY.DAT\s+\d+\s+([A-Za-z0-9: ]+)$//m) {
        print "Timestamp of $path not found in '$output'\n";
        return 0;
    }
    my $timestamp = $1;

    my $strp = DateTime::Format::Strptime->new(
        pattern   => '%a %b %e %H:%M:%S %Y',
        );
    my $dt = $strp->parse_datetime( $timestamp );
    my $epoch = $dt->strftime("%s");
    print " $handle/$timestamp => $epoch\n";

    $finfo->{signingHandle} = $handle;
    $finfo->{innerTimestamp} = $epoch;
    $finfo->{currentLength} = $finfo->{length};
    $finfo->{checkedLength} = $finfo->{length};
    $finfo->{seqno} = ++$globalCheckedFilesCount;
    return 1;
}

sub checkCommonFile {
    if (scalar(@pendingPaths) == 0) {
        loadCommonFiles();
        return;
    }
    my $filename = shift @pendingPaths;
    return unless defined $filename && $filename =~ /[.]mfz$/;
    if (length($filename) > $MAX_MFZ_NAME_LENGTH) {  #### XXX WOAH
        print "MFZ filename too long '$filename'\n";
        return;
    }

    my $path = "$commonDir/$filename";
    my $finfo = getFinfo($filename);

    # Check if file is incomplete
    if ($finfo->{currentLength} < $finfo->{length}) {
        requestFileChunk($finfo);
        return; # and that's all we do for now.
    }

    # Check if modtime change
    my $modtime = -M $path;
    if ($modtime != $finfo->{modtime}) {
        print "MODTIME CHANGE $path\n";
        $finfo->{modtime} = $modtime;
        $finfo->{checksum} = undef;
        $finfo->{innerTimestamp} = undef;
    }

    # Need checksum?
    if (!defined $finfo->{checksum}) {
        $finfo->{checksum} = checksumWholeFile($path);
        return; # That's enough for now..
    }

    # Need MFZ info?
    if (checkMFZDataFor($finfo)) {
        return; # That's plenty for now..
    }

    # This file is ready.  Maybe announce it to somebody?
    my $aliveNgb = getRandomAliveNgb();
    return unless defined $aliveNgb && oneIn(3);
    announceFileTo($aliveNgb,$finfo);
}

### MAJOR BATTLE DAMAGE REPORTING SIR
# sub getRemoteFinfo {
#     my ($filename, $length, $checksum, $time, $dir, $remoteSeqno) = @_;
#     defined $remoteSeqno or die;
#     my $path = "$commonDir/$filename";
#     my $finfo = $dataModel{$path};
#     if (!defined($finfo)) {
#         if (-r $path) {
#             $finfo = newFinfoExisting($path,$filename);
#             if (defined($finfo->{seqno})) {  # If we have a completed record..
#                 if ($checksum ne $finfo->{checksum}) {
#                     # Uh-oh, we have a conflict on a name.
#                     # Largest inner timestamp wins
#                     if ($time < $finfo->{innerTimestamp}) {
#                         # We win.  Tell caller to screw off
#                         return undef;
#                     }
#                 }
#             } else {
#                 return undef; # We are still developing our own record.  Screw yours for now.
#             }
#         } else {
#             # Here if we have no local file for remote content.
#         }
#     }
#     ## We're here if we've never heard of this content,
#     ## or we have an incomplete record
#     $finfo = {
#             path => $path,
#             filename => $filename,
#             length => $length,
#             modtime => undef,
#             checksum => undef,
#             signingHandle => undef,
#             innerTimestamp => undef,
#             seqno => undef,
#             otherSeqnos => [],
#         };
#     }
# }

sub newFinfoExisting {
    my ($path,$filename) = @_;
    die unless defined $path && -r $path;
    return {
        path => $path,
        filename => $filename,
        length => -s _,
        modtime => -M _,
        checksum => undef,
        signingHandle => undef,
        innerTimestamp => undef,
        seqno => undef,
        currentLength => -s _,
        checkedLength => 0,
        otherSeqnos => [],
    };
}

sub getFinfo {
    my $filename = shift;
    my $path = "$commonDir/$filename";
    my $finfo;
    while (!defined($finfo = $dataModel{$path})) {
        $dataModel{$path} = newFinfoExisting($path,$filename);
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

sub getLenArgFrom {
    my ($lenPos,$bref) = @_;
    my $len = ord($bref->[$lenPos]);
    my $content = join("",@$bref[$lenPos+1..$lenPos+$len]);
    my $nextLenPos = $lenPos+$len+1;
    return ($content,$nextLenPos);
}

sub addLenArgTo {
    my ($str,$arg) = @_;
    $str .= chr(length($arg)).$arg;
    return $str;
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

sub announceFileTo {
    my ($aliveNgb,$finfo) = @_;
    die unless defined $finfo->{seqno};
    my $fileAnnouncementCode = "F";
    my $pkt = chr(0x80+$aliveNgb->{dir}).chr($CDM_PKT_TYPE).$fileAnnouncementCode;
    $pkt = addLenArgTo($pkt,$finfo->{filename});
    $pkt = addLenArgTo($pkt,$finfo->{length});
    $pkt = addLenArgTo($pkt,$finfo->{checksum});
    $pkt = addLenArgTo($pkt,$finfo->{innerTimestamp});
    $pkt = addLenArgTo($pkt,$finfo->{seqno});
    print STDERR "ANNOUNCE($pkt)\n";
    writePacket($pkt);
}

sub touchFile {
    my $path = shift;
    open TMP, ">", $path or die "Can't touch $path: $!";
    close TMP or die "Can't close touched $path: $!";
}

sub checkAnnouncedFile {
    my ($filename,$contentLength,$checksum,$timestamp,$seqno,$dir) = @_;
    die unless defined $dir;

    ## Ignore complete and matched in common
    my $commonPath = "$commonDir/$filename";
    my $finfo = $dataModel{$commonPath};
    return if # ignore announcement 
        defined $finfo               # exists
        && defined $finfo->{seqno}   # and is complete
        && $finfo->{checksum} eq $checksum;  # and matches
    return if # ignore announcement 
        defined $finfo               # exists
        && !defined $finfo->{seqno}; # but isn't complete

    ## Create in pending if absent from common and pending
    my $pendingPath = "$pendingDir/$filename";
    my $pfinfo = $dataModel{$pendingPath};
    if (!defined($finfo) && !defined($pfinfo)) {
        $pfinfo = {
            path => $pendingPath,
            filename => $filename,
            length => $contentLength,
            modtime => undef,
            checksum => $checksum,
            signingHandle => undef,
            innerTimestamp => $timestamp,
            seqno => undef,  # local seqno not set til complete
            currentLength => 0,
            checkedLength => 0,
            otherSeqnos => [],
        };
        $pfinfo->{otherSeqnos}->[$dir] = $seqno;
        touchFile($pendingPath);
        $dataModel{$pendingPath} = $pfinfo;
        return;
    }

    ## Matched in pending: Refresh sku
    if (!defined($finfo) && defined($pfinfo)) {
        $pfinfo->{otherSeqnos}->[$dir] = $seqno;
        return;
    }

    ## Complete but mismatch in common
    if (defined($finfo) 
        && defined($finfo->{seqno})
        && $finfo->{checksum} ne $checksum) {
        print STDERR "COMMON CHECKSUM MISMATCH UNIMPLEMENTED, IGNORED $filename\n";
        return;
    }

    ## Complete but mismatch in common
    if (defined($pfinfo) 
        && defined($pfinfo->{seqno})
        && $pfinfo->{checksum} ne $checksum) {
        print STDERR "PENDING CHECKSUM MISMATCH UNIMPLEMENTED, IGNORED $filename\n";
        return;
    }
}

sub processFileAnnouncement {
    my @bytes = @_;
    my $bref = \@bytes;
    my $dir = ord($bytes[0])&0x7;
    # [0:2] known to be CDM F type
    my $lenPos = 3;
    my ($filename, $contentLength, $checksum, $timestamp, $seqno);
    ($filename,$lenPos) = getLenArgFrom($lenPos,$bref);
    ($contentLength,$lenPos) = getLenArgFrom($lenPos,$bref);
    ($checksum,$lenPos) = getLenArgFrom($lenPos,$bref);
    ($timestamp,$lenPos) = getLenArgFrom($lenPos,$bref);
    ($seqno,$lenPos) = getLenArgFrom($lenPos,$bref);
    if (scalar(@bytes) != $lenPos) {
        print "Expected $lenPos bytes got ".scalar(@bytes)."\n";
    }
    print "AF(fn=$filename,cs=$checksum,ts=$timestamp,seq=$seqno)\n";
    checkAnnouncedFile($filename,$contentLength,$checksum,$timestamp,$seqno,$dir);
}

sub getSKUForDir {
    my ($finfo,$dir) = @_;

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
        if ($bytes[2] eq "F") {
            processFileAnnouncement(@bytes);
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
}

sub main {
    checkInitDirs();
    openPackets();
    eventLoop();
    closePackets();
}

main();
exit 9;


