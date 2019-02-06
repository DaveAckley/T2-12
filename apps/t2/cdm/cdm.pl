#!/usr/bin/perl -w  # -*- perl -*-
use Fcntl;
use File::Path qw(make_path remove_tree);
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

my $baseDir = "/cdm";
my $commonSubdir = "common";
my $pendingSubdir = "pending";
my @subDirs = ($commonSubdir, $pendingSubdir);
my $commonPath = "$baseDir/$commonSubdir";
my $pendingPath = "$baseDir/pending";

sub flushPendingDir {
    my $count = remove_tree($pendingPath);
    if ($count > 1) {
        print "Flushed $count $pendingPath files\n";
    }
}

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

    checkInitDir($baseDir);

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

## hash of dir -> hash of filename -> finfo
my %cdmModel = map { ($_, {}) } @subDirs;

my @pathsToLoad;
my %hoodModel;

sub loadCommonFiles {
    if (!opendir(COMMON, $commonPath)) {
        print "WARNING: Can't load $commonPath: $!\n";
        return;
    }
    @pathsToLoad = shuffle readdir COMMON;
    closedir COMMON or die "Can't close $commonPath: $!\n";
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
my %seqnoMap;

sub assignSeqnoForFilename {
    my $filename = shift;
    my $seqno = ++$globalCheckedFilesCount;
    $seqnoMap{$seqno} = $filename;
    return $seqno;
}

sub getFinfoPath {
    my $finfo = shift;
    my $subdir = $finfo->{subdir} or die;
    my $filename = $finfo->{filename} or die;
    return "$baseDir/$subdir/$filename";
}

sub checkMFZDataFor {
    my $finfo = shift;
    return 0 if defined $finfo->{seqno}; # Or some refreshment maybe?

    #### REPLACE THIS WITH 'mfzrun VERIFY' ONCE AVAILABLE
    my $path = getFinfoPath($finfo);
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
    $finfo->{seqno} = assignSeqnoForFilename();
    return 1;
}

sub checkAndReleasePendingFile {
    my $finfo = shift;
    die "GOT THERE $finfo";
}

sub lexDecode {
    my $lex = shift;
    if ($lex =~ s/^9//) {
        my ($len,$rest) = lexDecode($lex);
        my $num = substr($rest,0,$len);
        substr($rest,0,$len) = "";
        return ($num,$rest);
    } elsif ($lex =~ s/^([0-8])//) {
        my $len = $1;
        my $num = substr($lex,0,$len);
        substr($lex,0,$len) = "";
        return ($num,$lex);
    } else {
        return undef;
    }
}

sub lexEncode {
    my $num = shift;
    my $len = length($num);
    return $len.$num if $len < 9;
    return "9".lexEncode($len).$num;
}

sub generateSKU {
    my ($finfo, $seqno) = @_;
    my $sku = sprintf("%s%02x%02x%03d%s",
                      substr($finfo->{filename},0,1),
                      ord(substr($finfo->{checksum},0,1)),
                      ord(substr($finfo->{checksum},1,1)),
                      $finfo->{innerTimestamp}%1000,
                      lexEncode($seqno));
    print "SKU($sku)\n";
    return $sku;
}

sub checkSKU {
    my $sku = shift;
    $sku =~ /^(.)([0-9a-fA-F]{2})([0-9a-fA-F]{2})(\d\d\d)(.+)$/
        or return undef;
    my ($fnchar,$cs0,$cs1,$bottim,$lexsi) = ($1,hex($2),hex($3),$4,$5);
    my $seqno = lexDecode($lexsi);
    defined $seqno or return undef;

    my $filename = $seqnoMap{$seqno};
    defined $filename or return undef;
    substr($filename,0,1) eq $fnchar or return undef;
    ord(substr($finfo->{checksum},0,1)) == $cs0 or return undef;
    ord(substr($finfo->{checksum},1,1)) == $cs1 or return undef;
    $finfo->{innerTimestamp}%1000 == $bottim or return undef;

    return $finfo;
}

sub checkPendingFile {
    # Pick a random pending
    my $pref = getSubdirModel($pendingSubdir);
    my @fnames = keys %{$pref};
    my $count = scalar @fnames;
    return unless $count > 0;

    my $filename = $fnames[createInt($count)];
    my $finfo = $pref->{$filename};
    my $len = $finfo->{length};
    my $cur = $finfo->{currentLength};
    if ($len == $cur) {
        checkAndReleasePendingFile($finfo);
        return;
    }
    if ($finfo->{timeCount} > 0) {
        --$finfo->{timeCount};
        return;
    }
    my ($dir,$seqno) = selectProvider($finfo);
    if (!defined($dir) || !defined($seqno)) {
        print "No provider found for $filename in $finfo?\n";
        return;
    }
    my $sku = generateSKU($finfo,$seqno);

    my $contentRequestCode = "C";
    my $pkt = chr(0x80+$dir).chr($CDM_PKT_TYPE).$contentRequestCode;
    $pkt = addLenArgTo($pkt,$sku);
    $pkt = addLenArgTo($pkt,$cur);
    $finfo->{timeCount} = 1;  # don't spam requests too fast
    print STDERR "REQUEST($pkt)\n";
    writePacket($pkt);
}

sub checkCommonFile {
    if (scalar(@pathsToLoad) == 0) {
        loadCommonFiles();
        return 1; # did work
    }
    my $filename = shift @pathsToLoad;
    return unless defined $filename && $filename =~ /[.]mfz$/;
    if (length($filename) > $MAX_MFZ_NAME_LENGTH) {  #### XXX WOAH
        print "MFZ filename too long '$filename'\n";
        return 1;
    }

    my $finfo = getFinfoFromCommon($filename);
    my $path = getFinfoPath($finfo) || die "No path";

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
        return 1; # That's enough for now..
    }

    # Need MFZ info?
    if (checkMFZDataFor($finfo)) {
        return 1; # That's plenty for now..
    }

    # This file is ready.  Maybe announce it to somebody?
    my $aliveNgb = getRandomAliveNgb();
    if (defined $aliveNgb && oneIn(3)) {
        announceFileTo($aliveNgb,$finfo);
        return 1;
    }
    return 0; # didn't do any 'real' work..
}

# For files we have locally and completely
sub newFinfoLocal {
    my ($filename,$indir) = @_;
    my $finfo = newFinfoBare($filename);
    $finfo->{subdir} = $indir;
    my $path = getFinfoPath($finfo);
    die "Can't read $path: $!" unless defined $path && -r $path;
    $finfo->{length} = -s _;
    $finfo->{modtime} = -M _;
    $finfo->{currentLength} = -s _;
    return $finfo;
}

sub newFinfoBare {
    my ($filename) = @_;
    defined $filename or die;
    return {
        filename => $filename,
        subdir => undef,
        length => undef,
        modtime => undef,
        checksum => undef,
        signingHandle => undef,
        innerTimestamp => undef,
        seqno => undef,
        currentLength => undef,
        checkedLength => 0,
        timeCount => 0,
        otherSeqnos =>[],
    };
}

sub selectProvider {
    my $finfo = shift;
    my $sdir;
    my $sseq;
    my $count = 0;
    for (my $dir = 0; $dir < 8; ++$dir) {
        my $seq = $finfo->{otherSeqnos}->[$dir];
        if (defined($seq) && oneIn(++$count)) {
            $sdir = $dir;
            $sseq = $seq;
        }
    }
    return ($sdir,$sseq);
}

sub refreshProvider {
    my ($finfo,$dir,$seq) = @_;
    my $ageDir = randDir();
    # Age out one dir (might be empty)
    $finfo->{otherSeqnos}->[$ageDir] = undef;

    # Refresh us
    $finfo->{otherSeqnos}->[$dir] = $seq;
    print "FRESH $dir $finfo ".$finfo->{filename}." ".$finfo->{otherSeqnos}->[$dir]."\n";
}

sub getFinfoFromCommon {
    my $filename = shift;
    return getFinfoFrom($filename,$commonSubdir);
}
sub getFinfoFromPending {
    my $filename = shift;
    return getFinfoFrom($filename,$pendingSubdir);
}

sub getSubdirModel {
    my $subdir = shift;
    my $href = $cdmModel{$subdir};
    defined $href or die "Bad subdir '$subdir'";
    return $href
}

sub getFinfoFrom {
    my ($filename,$subdir) = @_;
    my $href = getSubdirModel($subdir);
    my $finfo;
    while (!defined($finfo = $href->{$filename})) {
        $href->{$filename} = newFinfoLocal($filename,$subdir);
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

sub createInt {
    my $max = shift;
    my $imax = int($max);
    die if $imax < 1;
    return int(rand($imax));
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
    return if checkCommonFile();

    # PENDING MGMT
    return if checkPendingFile();
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
    my $commonref = getSubdirModel($commonSubdir);
    my $finfo = $commonref->{$filename};
    return if # ignore announcement if the file
        defined $finfo               # exists
        && defined $finfo->{seqno}   # and is complete
        && $finfo->{checksum} eq $checksum;  # and matches
    return if # also ignore announcement if the file
        defined $finfo               # exists
        && !defined $finfo->{seqno}; # but isn't complete

    ## Create in pending if absent from common and pending
    my $pendingref = getSubdirModel($pendingSubdir);
    my $pfinfo = $pendingref->{$filename};
    if (!defined($finfo) && !defined($pfinfo)) {
        
        $pfinfo = newFinfoBare($filename);
        $pfinfo->{length} = $contentLength;
        $pfinfo->{checksum} = $checksum;
        $pfinfo->{innerTimestamp} = $timestamp;
        $pfinfo->{currentLength} = 0;
        $pfinfo->{checkedLength} = 0;
        refreshProvider($pfinfo,$dir,$seqno);
        touchFile("$pendingPath/$filename");

        $pendingref->{$filename} = $pfinfo;
        return;
    }

    ## Matched in pending: Refresh sku
    if (!defined($finfo) && defined($pfinfo)) {
        refreshProvider($pfinfo,$dir,$seqno);
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

sub processChunkRequest {
    my @bytes = @_;
    my $bref = \@bytes;
    my $dir = ord($bytes[0])&0x7;
    # [0:2] known to be CDM C type
    my $lenPos = 3;
    my ($sku, $startingIndex);
    ($sku,$lenPos) = getLenArgFrom($lenPos,$bref);
    ($startingIndex,$lenPos) = getLenArgFrom($lenPos,$bref);
    my $finfo = checkSKU($sku);
    if (!defined($finfo)) {
        print "Bad SKU $sku\n";
        return;
    }
    my $filename = $finfo->{filename};
    print "CR(sku=$sku,fn=$filename,si=$startingIndex)\n";
    # XXXX DO ME DO ME
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
        if ($bytes[2] eq "C") {
            processChunkRequest(@bytes);
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
    flushPendingDir();
    checkInitDirs();
    openPackets();
    eventLoop();
    closePackets();
}

main();
exit 9;


