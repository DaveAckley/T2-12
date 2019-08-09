#!/usr/bin/perl -w  # -*- perl -*-
use Fcntl;
use File::Path qw(make_path remove_tree);
use File::Basename;
use File::Copy qw(move copy);
use Errno qw(EAGAIN);
use Time::HiRes;
use List::Util qw/shuffle/;
use Digest::SHA qw(sha512_hex);
use DateTime::Format::Strptime;

use warnings FATAL => 'all';
$SIG{__DIE__} = sub {
    die @_ if $^S;
    require Carp; 
    Carp::confess ;
};

my $CDM_PKT_TYPE = 0x03;
my $CDM_PKT_TYPE_BYTE = chr($CDM_PKT_TYPE);

my $MAX_MFZ_NAME_LENGTH = 28+4; # 4 for '.mfz'

my $pktdev = "/dev/itc/packets";
my $mode = O_RDWR|O_NONBLOCK;

my @dirnames = ("NT", "NE", "ET", "SE", "ST", "SW", "WT", "NW");

my $DEBUG_FLAG_PACKETS = 1;
my $DEBUG_FLAG_DEBUG = $DEBUG_FLAG_PACKETS<<1;
my $DEBUG_FLAG_STANDARD = $DEBUG_FLAG_DEBUG<<1;
my $DEBUG_FLAG_VERBOSE = $DEBUG_FLAG_STANDARD<<1;
my $DEBUG_FLAG_ALL = 0xffffffff;

my $DEBUG_FLAGS = $DEBUG_FLAG_STANDARD;

#my %triggerMFZs = ( 'cdm-triggers.mfz' => &updateTriggers );
# Hardcode deletions only, for now
my %triggerMFZs = (
    'cdm-deleteds.mfz' => \&updateDeleteds,
    'cdmd-MFM.mfz' => \&installCDMDMFM,
    'cdmd-T2-12.mfz' => \&installCDMDT2_12,
#DEPRECATED    'cdmd-T2-GFB.mfz' => \&installCDMDGFB,
#DEPRECATED    'cdmd-t2.mfz' => \&installOverlay,
    );
my %cdmdTargetDirs = (
    'cdmd-MFM.mfz' => "/home/t2/GITHUB",
    'cdmd-T2-12.mfz' => "/home/t2",
#DEPRECATED    'cdmd-T2-GFB.mfz' => "/home/t2/GITHUB/GFB",
#DEPRECATED    'cdmd-t2.mfz' => "/home",
    );

sub DPF {
    my ($flags,$msg) = @_;
    return unless $DEBUG_FLAGS & $flags;
    print "$msg\n";
}

sub DPPKT { DPF($DEBUG_FLAG_PACKETS,shift); }
sub DPSTD { DPF($DEBUG_FLAG_STANDARD,shift); }
sub DPVRB { DPF($DEBUG_FLAG_VERBOSE,shift); }
sub DPDBG { DPF($DEBUG_FLAG_DEBUG,shift); }

sub getDirName {
    my $dir = shift;
    die unless defined $dir;
    return $dirnames[$dir] if defined $dirnames[$dir];
    return "Bad dir '$dir'";
}

sub openPackets {
    sysopen(PKTS, $pktdev, $mode) or die "Can't open $pktdev: $!";
}

sub flushPackets {
    my ($pkts,$len)=(0,0);
    while ( my $pkt = readPacket() ) {
        ++$pkts;
        $len += length($pkt);
    }
    DPSTD("Discarded $pkts packet(s) containing $len byte(s)");
}

sub readPacket {
    my $pkt;
    my $count;
    if (defined($count = sysread(PKTS, $pkt, 512))) {
        return if $count == 0;
        DPPKT("GOT PACKET($pkt)");
        return $pkt;
    }
    return undef;
}
        

sub writePacket {
    my ($pkt,$ignoreUnreach) = @_;
    $ignoreUnreach ||= 1; # Default to ignore unreachable hosts
    my $usec = 1000;
    while (1) {
        my $len = syswrite(PKTS, $pkt);
        return 1 if defined $len;
        if ($ignoreUnreach && $!{EHOSTUNREACH}) {
            DPPKT("Host unreachable, ignored");
            return;
        }
        die "Error: $!" unless $!{EAGAIN};
        DPVRB("WRITE BLOCKING");
        Time::HiRes::usleep($usec += 1000);
        if ($usec > 500000) {
            my $pru = "/sys/class/itc_pkt/pru_bufs";
            my $bufs = do{local(@ARGV,$/)=$pru;<>};
            chomp $bufs;
            DPSTD(sprintf("WritePacket timed out on 0x%02x/%d\n%s",ord($pkt),length($pkt),$bufs));
            return;
        }
    }
}

sub closePackets {
    close(PKTS) or die "Can't close $pktdev: $!";
}

my $baseDir = "/cdm";
my $commonSubdir = "common";
my $pendingSubdir = "pending";
my $logSubdir = "log";
my $pubkeySubdir = "public_keys";
my @subDirs = ($commonSubdir, $pendingSubdir,$logSubdir,$pubkeySubdir);
my $commonPath = "$baseDir/$commonSubdir";
my $pendingPath = "$baseDir/pending";

my $mfzrunProgPath = "/home/t2/GITHUB/MFM/bin/mfzrun";

sub flushPendingDir {
    my $count = remove_tree($pendingPath);
    if ($count > 1) {
        DPSTD("Flushed $count $pendingPath files");
    }
}

sub checkInitDir {
    my $dir = shift;
    if (-d $dir) {
        DPSTD("Found $dir");
        return 1;
    }
    if (-e $dir) {
        DPSTD("$dir exists but is not a directory");
        return 0;
    }
    if (make_path($dir)) {
        DPSTD("Made $dir");
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

    # Ensure our base key is in there
    my $keyPath = "$baseDir/$pubkeySubdir/t2%2dkeymaster%2drelease%2d10.pub";
    if (!(-e $keyPath)) {
        print "Initting $keyPath\n";
        open HDL,">",$keyPath or die "Can't write $keyPath: $!";
        print HDL <<'EOF';
[MFM-Handle:t2-keymaster-release-10]
-----BEGIN RSA PUBLIC KEY-----
MIGJAoGBAMUbUl/GDrkKYB3ORkeetZEkKisfgiwl6TgoqAB7dfK1gGN3bzDyz/+A
LisTyW0b+64ePqv1liBxJEBOd2eX9+hTnngasOrb8RIQN6vTPg6+3WGAmgtez3kg
5KSeBLlgMaEbKkeOXZU+pbAaUzL6EGr/O/ESdTE6Lh6azq2DR3P7AgMBAAE=
-----END RSA PUBLIC KEY-----
EOF
      close HDL or die "Close $keyPath: $!";
    }
}

sub sendCDMTo {
    my ($dest, $type, $args) = @_;
    die if $dest < 1 or $dest > 7 or $dest == 4;
    die if length($type) != 1;
    my $pkt = chr(0x80+$dest).chr($CDM_PKT_TYPE).$type;
    $pkt .= $args if defined $args;
    DPPKT("SENDIT($pkt)");
    writePacket($pkt);
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

sub loadCommonMFZFiles {
    if (!opendir(COMMON, $commonPath)) {
        DPSTD("WARNING: Can't load $commonPath: $!");
        return;
    }
    @pathsToLoad = grep { /[.]mfz$/ } shuffle readdir COMMON;
    closedir COMMON or die "Can't close $commonPath: $!\n";
}

my $digester = Digest::SHA->new(256);

sub checksumWholeFile {
    my $path = shift;
    $digester->reset();
    $digester->addfile($path);
    my $cs = substr($digester->digest(),0,16);
    my $hexcs = unpack("H*",$cs);
    DPVRB(" $path => $hexcs");
    return $cs;
}

my $globalCheckedFilesCount = 0;
my %seqnoMap;

sub assignSeqnoForFilename {
    my $filename = shift;
    die unless defined $filename;
    my $seqno = ++$globalCheckedFilesCount;
    $seqnoMap{$seqno} = $filename;
    DPSTD("Assigning seqno $seqno for $filename");
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
    my $cmd = "echo Q | mfzrun -kd /cdm $path list";
    my $output = `$cmd`;

    if ($output =~ /.*?signer handle '(:?[a-zA-Z][-., a-zA-Z0-9]{0,62})' is not recognized!/) {
        my $badhandle = $1;
        DPSTD("Unrecognized handle '$badhandle' in $path");
        return 0;
    }
    if ($output !~ s/^SIGNED BY RECOGNIZED HANDLE: (:?[a-zA-Z][-., a-zA-Z0-9]{0,62}) \(//) {
        DPSTD("Handle of $path not found in '$output'");
        return 0;
    }
    my $handle = $1;
    if ($output !~ s/^\s+MFZPUBKEY.DAT\s+\d+\s+([A-Za-z0-9: ]+)$//m) {
        DPSTD("Timestamp of $path not found in '$output'");
        return 0;
    }
    my $timestamp = $1;

    my $strp = DateTime::Format::Strptime->new(
        pattern   => '%a %b %e %H:%M:%S %Y',
        );
    my $dt = $strp->parse_datetime( $timestamp );
    my $epoch = $dt->strftime("%s");
    DPSTD(" $path: $handle/$timestamp => $epoch");

    $finfo->{signingHandle} = $handle;
    $finfo->{innerTimestamp} = $epoch;
    $finfo->{currentLength} = $finfo->{length};
    $finfo->{checkedLength} = $finfo->{length};
    return 1;
}

sub killPending {
    my ($finfo, $reason) = @_;
    my $filename = $finfo->{filename};
    my $subdir = $finfo->{subdir};
    $subdir or die "No subdir";
    my $path = getFinfoPath($finfo);
    unlink $path;
    DPSTD("Purged pending '$path': $reason");
    $finfo->{purgatory} = 1;
}

sub updateDeleteds {
    my ($finfo) = @_;
    print "UPDATE DELETEDS YA WOBBO '".join(", ",keys %{$finfo})."'\n";
}

my $debugPanelShouldBeDisplayed = 0;
sub installCDMDGFB {
    my ($finfo) = @_;
    installCDMD($finfo);
    if ($debugPanelShouldBeDisplayed) {
        toggleDebugPanel();
        sleep 1;
        toggleDebugPanel();
    }
}

sub installSetup {
    my ($finfo) = @_;
    my $fname = $finfo->{filename};
    if ($fname !~ /^cdmd-([^.]+)[.]mfz$/) {
        print "INSTALL '$fname': Malformed filename, ignoring\n";
        return;
    }
    my $baseName = $1;
    my $dirName = $cdmdTargetDirs{$fname};
    if (!defined $dirName) {
        print "INSTALL '$fname': No CDMD target, ignoring\n";
        return;
    }
    print "INSTALL found candidate $baseName -> $dirName\n";
    my $tagFileName = "$dirName/$fname-cdm-install-tag.dat";
    my $innerTimestamp = $finfo->{innerTimestamp};
    if (-r $tagFileName) {
        open my $fh,'<',$tagFileName or die "Can't read $tagFileName: $!";
        my $line = <$fh>;
        close $fh or die "close $tagFileName: $!";
        $line ||= "";
        chomp $line;
        if ($line !~ /^([0-9]+)$/) {
            print "INSTALL Ignoring malformed $tagFileName ($line)\n";            
        } else {
            my $currentTimestamp = $1;
            if ($innerTimestamp == $currentTimestamp) {
                print "INSTALL $baseName: We are up to date; nothing to do\n";
                return;
            }
            if ($innerTimestamp < $currentTimestamp) {
                print "INSTALL $baseName: Candidate appears outdated ($innerTimestamp vs $currentTimestamp)\n";
                print "INSTALL $baseName: NOT INSTALLING. Delete $tagFileName to allow this install\n";
                return;
            }
        }
        print "INSTALL $tagFileName -> INSTALLING UPDATE\n";
    } 
    return ($fname, $baseName, $dirName, $tagFileName, $innerTimestamp);
}

sub installUnpack {
    my ($fname, $baseName, $dirName, $tagFileName, $innerTimestamp) = @_;

    ### DO UNPACK
    print "INSTALL $baseName: Starting install\n";
    my $tmpDirName = "$dirName/$baseName-cdm-install-tmp";
    print "INSTALL $baseName: (1) Clearing $tmpDirName\n";

    return unless runCmdWithSync("rm -rf $tmpDirName","INSTALL $baseName: ERROR");
    return unless runCmdWithSync("mkdir -p $tmpDirName","INSTALL $baseName: ERROR");

    my $mfzPath = "$commonPath/$fname";
    print "INSTALL $baseName: (2) Unpacking $mfzPath\n";

    return unless runCmdWithSync("$mfzrunProgPath -kd /cdm $mfzPath unpack $tmpDirName","INSTALL $baseName: ERROR");

    print "INSTALL $baseName: (3) Finding tgz\n";
    my $tgzpath;
    {
        my $cmd = "find $tmpDirName -name '*.tgz'";
        my $output = `$cmd`;
        chomp $output;
        print "INSTALL $baseName: (3.1) GOT ($output)\n";
        my @lines = split("\n",$output);
        my $count = scalar(@lines);
        if ($count != 1) {
            print "INSTALL $baseName: ABORT: FOUND $count LINES\n";
            return;
        }
        $tgzpath = $lines[0];
    }
    my $targetSubDir = "$tmpDirName/tgz";
    print "INSTALL $baseName: (4) Clearing '$targetSubDir'\n";
    return unless runCmdWithSync("rm -rf $targetSubDir","INSTALL $baseName: ERROR");
    return unless runCmdWithSync("mkdir -p $targetSubDir","INSTALL $baseName: ERROR");

    print "INSTALL $baseName: (5) Unpacking '$tgzpath' -> $targetSubDir\n";
    my $initialBaseNameDir;
    return unless runCmdWithSync("tar xf $tgzpath -m --warning=no-timestamp -C $targetSubDir","INSTALL $baseName: ERROR");

    $initialBaseNameDir = "$targetSubDir/$baseName";
    if (!(-r $initialBaseNameDir && -d $initialBaseNameDir)) {
        print "INSTALL $baseName: (5.1) ABORT: '$initialBaseNameDir' not readable dir\n";            
        return;
    }

    return ($tmpDirName, $mfzPath, $tgzpath, $targetSubDir, $initialBaseNameDir);
}

sub runCmdWithSync {
    my ($btcmd,$errprefix) = @_;
    `$btcmd && sync`; 
    if ($?) { print "$errprefix: '$btcmd' returned code $?\n"; return 0; }
    return 1;
}

sub installCDMDT2_12 {
    return unless defined installCDMD(@_);
    print "INSTALLING T2-12\n";
    return unless runCmdWithSync("cd /home/t2/T2-12 && make install","T2-12: make install: ERROR");
    print "EXITING TO RESTART\n";
    exit 17;
}

sub installCDMDMFM {
    return unless defined installCDMD(@_);
    my $mfmt2pid = `ps -C mfmt2 -o pid=`;
    chomp $mfmt2pid;
    if ($mfmt2pid =~ /^[0-9]+$/) {
        print "KILLING mfmt2($mfmt2pid)\n";
        kill 'INT', $mfmt2pid;
    }
    return;
}

sub installCDMD { # return undef unless install actually happened
    my ($finfo) = @_;
    my @args = installSetup($finfo);
    return if scalar(@args) == 0;  # Something went wrong, or nothing to do
    my ($fname, $baseName, $dirName, $tagFileName, $innerTimestamp) = @args;

    my @moreargs = installUnpack($fname, $baseName, $dirName, $tagFileName, $innerTimestamp );
    return if scalar(@moreargs) == 0;
    my ($tmpDirName, $mfzPath, $tgzpath, $targetSubDir, $initialBaseNameDir) = @moreargs;
    
    ### DO FULL DIR MOVE REPLACEMENT
    my $prevDirName = "$dirName/$baseName-cdm-install-prev";
    print "INSTALL $baseName: (6) Clearing $prevDirName\n";

    return unless runCmdWithSync("rm -rf $prevDirName","INSTALL $baseName: ERROR");

    return unless runCmdWithSync("mkdir -p $prevDirName","INSTALL $baseName: ERROR");

    my $finalDirName = "$dirName/$baseName";
    print "INSTALL $baseName: (7) Moving $finalDirName to $prevDirName\n";
    return unless runCmdWithSync("mv $finalDirName $prevDirName","INSTALL $baseName: ERROR");

    print "INSTALL $baseName: (8) Moving $initialBaseNameDir to $finalDirName\n";
    return unless runCmdWithSync("mv $initialBaseNameDir $finalDirName","INSTALL $baseName: ERROR");

    print "INSTALL $baseName: (9) Tagging install $tagFileName -> $innerTimestamp\n";
    {
        my $fh;
        if (!(open $fh,'>',$tagFileName)) {
            print "INSTALL $baseName: WARNING: Can't write $tagFileName: $!\n";
            return;
        }
        print $fh "$innerTimestamp\n";
        close $fh or die "close $tagFileName: $!";
    } 

    print "INSTALLED '$fname'\n";
    return 1;
}

sub installOverlay {
    my ($finfo) = @_;
    my @args = installSetup($finfo);
    return if scalar(@args) == 0;  # Something went wrong.
    my ($fname, $baseName, $dirName, $tagFileName, $innerTimestamp) = @args;

    my @moreargs = installUnpack($fname, $baseName, $dirName, $tagFileName, $innerTimestamp );
    return if scalar(@moreargs) == 0;
    my ($tmpDirName, $mfzPath, $tgzpath, $targetSubDir, $initialBaseNameDir) = @moreargs;
    
    ### DO IN-PLACE OVERLAY OF NEW INTO OLD
    my $prevDirName = "$dirName/$baseName-cdm-install-prev";
    print "INSTALL $baseName: (6) Clearing $prevDirName\n";
    return unless runCmdWithSync("rm -rf $prevDirName","INSTALL $baseName: ERROR");
    return unless runCmdWithSync("mkdir -p $prevDirName","INSTALL $baseName: ERROR");

    my $finalDirName = "$dirName/$baseName";
    print "INSTALL $baseName: (7a) NOT BACKING UP $finalDirName to $prevDirName!\n";

    print "INSTALL $baseName: (8a) COPYING $initialBaseNameDir INTO EXISTING $finalDirName\n";
    return unless runCmdWithSync("cp -af $initialBaseNameDir/. $finalDirName","INSTALL $baseName: ERROR");

    print "INSTALL $baseName: (9a) Tagging install $tagFileName -> $innerTimestamp\n";
    {
        my $fh;
        if (!(open $fh,'>',$tagFileName)) {
            print "INSTALL $baseName: WARNING: Can't write $tagFileName: $!\n";
            return;
        }
        print $fh "$innerTimestamp\n";
        close $fh or die "close $tagFileName: $!";
        return;
    } 

    print "INSTALL '$fname' (OVERLAID)\n";
}

sub checkTriggersAndAnnounce {
    my $finfo = shift;
    my $filename = $finfo->{filename};
    my $trigref = $triggerMFZs{$filename};
    &$trigref($finfo) if defined($trigref);

    my $count = 0;
    foreach my $k (shuffle(keys %hoodModel)) {
        my $v = $hoodModel{$k};
        if ($v->{isAlive}) {
            announceFileTo($v,$finfo);
            ++$count;
        }
    }
    DPSTD("ANNOUNCED $filename to $count");
}

sub checkAndReleasePendingFile {
    my $finfo = shift;

    DPDBG("checkAndReleasePendingFile $finfo");

    # Make sure the checksum matches
    my $path = getFinfoPath($finfo);
    my $localChecksum = checksumWholeFile($path);
    return killPending($finfo,"Bad checksum")
        if $localChecksum ne $finfo->{checksum};
    DPDBG("checkAndReleasePendingFile $localChecksum OK");

    return killPending($finfo,"Bad MFZ verify")
        if !checkMFZDataFor($finfo);

    DPDBG("checkAndReleasePendingFile MFZ verified OK");

    $finfo->{subdir} = $commonSubdir;
    my $newpath = getFinfoPath($finfo);
    move($path,$newpath) or die "Couldn't move $path -> $newpath: $!";

    my $filename = $finfo->{filename};
    my $pref = getSubdirModel($pendingSubdir);
    my $cref = getSubdirModel($commonSubdir);
    my $seqno = assignSeqnoForFilename($filename);
    $finfo->{seqno} = $seqno;
    $finfo->{modtime} = -M $newpath;
    DPDBG("checkAndReleasePendingFile MFZ modtime ".$finfo->{modtime});

    delete $pref->{$filename}; # Remove metadata from pending
    $cref->{$filename} = $finfo; # Add it to common
    DPSTD("RELEASED $filename");

    checkTriggersAndAnnounce($finfo);
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
    DPDBG("SKU($sku)");
    return $sku;
}

sub checkSKUInDir {
    my ($sku,$dir) = @_;
    defined $dir or die;
    $dir >= 0 && $dir <= 8 or die;
    my $subdir = ($dir == 8) ? $commonSubdir : $pendingSubdir;
    $sku =~ /^(.)([0-9a-fA-F]{2})([0-9a-fA-F]{2})(\d\d\d)(.+)$/
        or return undef;
    my ($fnchar,$cs0,$cs1,$bottim,$lexsi) = ($1,hex($2),hex($3),$4,$5);
    DPDBG("cdddsk ($fnchar,$cs0,$cs1,$bottim,$lexsi)");

    my ($seqno,undef) = lexDecode($lexsi);
    defined $seqno or return undef;

    my $filename;
    if ($dir == 8) {
        $filename = $seqnoMap{$seqno};
    } else {
        my $ngb = getNgbInDir($dir);
        $filename = $ngb->{contentOffered}->{$seqno};
    }
    defined $filename or return undef;
    substr($filename,0,1) eq $fnchar or return undef;

    my $finfo = getFinfoFrom($filename,$subdir);
    defined $finfo or return undef;
    DPDBG("cSKU finfo $finfo OK");
    ord(substr($finfo->{checksum},0,1)) == $cs0 or return undef;
    DPDBG("cSKU cs0 $cs0 OK");
    ord(substr($finfo->{checksum},1,1)) == $cs1 or return undef;
    DPDBG("cSKU cs1 $cs1 OK");
    $finfo->{innerTimestamp}%1000 == $bottim or return undef;
    DPDBG("cSKU ts $bottim OK");

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

    if (defined($finfo->{purgatory})) {
        delete $pref->{$filename} if oneIn(25); # Just ignore this guy for a while
        return;                                 # then delete him to try again
    }

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
    issueContentRequest($finfo);
}

sub issueContentRequest {
    my ($finfo) = @_;
    my $cur = $finfo->{currentLength};
    my $len = $finfo->{length};
    my $filename = $finfo->{filename};

    my ($dir,$seqno) = selectProvider($finfo);
    if (!defined($dir) || !defined($seqno)) {
        DPSTD("No provider found for $filename in $finfo?");
        return;
    }
    my $sku = generateSKU($finfo,$seqno);

    my $contentRequestCode = "C";
    my $pkt = chr(0x80+$dir).chr($CDM_PKT_TYPE).$contentRequestCode;
    $pkt = addLenArgTo($pkt,$sku);
    $pkt = addLenArgTo($pkt,$cur);
    $finfo->{timeCount} = 3;  # don't spam requests too fast
    DPPKT("REQUEST($pkt)");
    writePacket($pkt);
}

sub preinitCommon {
    DPSTD("Preloading common");
    my $count = 0;
    while (checkCommonFile(0)) {
        if (checkUserButton()) {
            toggleDebugPanel();
        }
        ++$count; 
    }
    DPVRB("Preload complete after $count steps");
}

my $lastCommonModtime = 0;
sub checkCommonFile {
    my $announceOK = shift;

    if (scalar(@pathsToLoad) == 0 ||
        (-M $commonPath != $lastCommonModtime)) {
        $lastCommonModtime = -M $commonPath;
        ## Between dir loads.  Let's check our finfos
        my $cref = getSubdirModel($commonSubdir);
        my $deaders = 0;
        my @finfos = values %{$cref};
        foreach my $finfo (@finfos) {
            my $path = getFinfoPath($finfo);
            
            # Check if file vanished
            if (!-e $path) {
                ++$deaders;
                DPSTD("Common file vanished: $path");
                # What to do with finfo??  Let's ditch it
                delete $cref->{$finfo->{filename}};
            }
        }
        return 1 if $deaders > 0;
        loadCommonMFZFiles();

        return (scalar(@pathsToLoad) > 0 ? 1 : 0); # did work
    }
    
    my $filename = shift @pathsToLoad;
    return 0 unless defined $filename; # ??
    if (length($filename) > $MAX_MFZ_NAME_LENGTH) {  #### XXX WOAH
        DPSTD("MFZ filename too long '$filename'");
        return 1;
    }

    my $finfo = getFinfoFromCommon($filename);
    my $path = getFinfoPath($finfo) || die "No path";

    # Don't continue, but didn't do work, if the file has vanished
    return 0 unless -e $path;
    
    # Check if modtime change
    my $modtime = -M $path;
    if (!defined($finfo->{modtime}) || $modtime != $finfo->{modtime}) {
        my $newlen = -s $path;
        DPSTD("MODTIME CHANGE $path size $newlen");
        $finfo->{modtime} = $modtime;
        $finfo->{length} = $newlen;
        $finfo->{currentLength} = $newlen;
        $finfo->{checksum} = undef;
        $finfo->{innerTimestamp} = undef;
        $finfo->{seqno} = undef;
    }

    # Need checksum?
    if (!defined $finfo->{checksum}) {
        $finfo->{checksum} = checksumWholeFile($path);
        return 1; # That's enough for now..
    }

    # Need MFZ info?
    if (checkMFZDataFor($finfo)) {
        # OK, it checked out.  Give it a seqno
        $finfo->{seqno} = assignSeqnoForFilename($finfo->{filename});
        # and run triggers on it, if any
        checkTriggersAndAnnounce($finfo);
        return 1; # That's plenty for now..
    }

    # Ensure it really is ready
    if (!defined($finfo->{seqno})) {
        DPSTD("FAILED TO VALIDATE '$path' -- deleting");
        my $cref = getSubdirModel($commonSubdir);
        delete $cref->{$filename};
        unlink $path or die "Couldn't unlink '$path'";
        return 1;
    }

    # This file is ready.  Announce it to a few folks?
    if ($announceOK) {
        my $announcements = 0;
        foreach my $ngb (getRandomAliveNgbList()) {
            announceFileTo($ngb,$finfo);
            ++$announcements;
            last if oneIn(3);
        }
        return 1 if $announcements > 0;
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
        currentLength => 0,
        checkedLength => 0,
        timeCount => 0,
        otherSeqnos =>[],
    };
}

sub dropProviderForSKU {
    my ($dir,$sku) = @_;
    my $pref = getSubdirModel($pendingSubdir);
    for my $finfo (values %{$pref}) {
        my $seq = $finfo->{otherSeqnos}->[$dir];
        next unless defined $seq;
        my $existingSKU = generateSKU($finfo,$seq);
        if (existingSKU eq $sku) {
            my $filename = $finfo->{filename};
            delete $pref->{$filename};
            DPSTD("Dropped $dir as provider of $sku");
            return;
        }
    }
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
    DPDBG("FRESH $dir $finfo ".$finfo->{filename}." ".$finfo->{otherSeqnos}->[$dir]);

    # Set/Update remote content-offered
    my $ngb = getNgbInDir($dir);
    $ngb->{contentOffered}->{$seq} = $finfo->{filename};
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
        contentOffered => {}, # seqno -> filename
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
    DPSTD("Undefined arg supplied at '$str'") unless defined $arg;
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

sub getRandomAliveNgbList {
    my @ngbs;
    foreach my $k (keys %hoodModel) {
        my $v = $hoodModel{$k};
        if ($v->{isAlive}) { push @ngbs, $v; }
    }
    return shuffle(@ngbs);
}

my $continueEventLoop = 1;
my $alivetag = int(rand(100));
sub doBackgroundWork {

    # ALIVENESS MGMT
    my $ngb = getRandomNgb();
    if ($ngb->{isAlive} && rand(++$ngb->{clacksSinceAliveRcvd}) > 50) {
        $ngb->{isAlive} = 0;
        DPSTD(getDirName($ngb->{dir})." is dead");
    }
    
    if (rand(++$ngb->{clacksSinceAliveSent}) > 5) {
#           print STDERR " ALV".$ngb->{dir}."\n";

        $ngb->{clacksSinceAliveSent} = 0;
        $alivetag = ($alivetag + 1)&0xff;
        sendCDMTo($ngb->{dir},'A',chr($alivetag));
    }

    # Record our liveness info for t2viz to viz
    my $statusDir = "/run/cdm";
    if (!-d $statusDir) {
        mkdir $statusDir or DPSTD("Can't create $statusDir: $!");
    }
    my $statusFile = "$statusDir/status.dat";
    if (!open(HANDLE,">",$statusFile)) { DPSTD("Can't open $statusFile: $!"); }
    else {
        my $now = now();
        for (my $dir = 0; $dir < 8; ++$dir) {
            my $ngb = getNgbInDir($dir);
            print HANDLE ($ngb->{isAlive} ? "1 " : "0 ");
        }
        print HANDLE "$now\n";
        close HANDLE or DPSTD("Can't close $statusFile: $!");
    }

    # COMMON MGMT
    checkCommonFile(1);

    # PENDING MGMT
    checkPendingFile();
}

sub announceFileTo {
    my ($aliveNgb,$finfo) = @_;
#    print STDERR " ANCE".$aliveNgb->{dir}.": ".$finfo->{filename}."+".$finfo->{innerTimestamp}."\n";

    die unless defined $finfo->{seqno};
    my $fileAnnouncementCode = "F";
    my $pkt = chr(0x80+$aliveNgb->{dir}).chr($CDM_PKT_TYPE).$fileAnnouncementCode;
    $pkt = addLenArgTo($pkt,$finfo->{filename});
    $pkt = addLenArgTo($pkt,$finfo->{length});
    $pkt = addLenArgTo($pkt,$finfo->{checksum});
    $pkt = addLenArgTo($pkt,$finfo->{innerTimestamp});
    $pkt = addLenArgTo($pkt,$finfo->{seqno});
    DPPKT("ANNOUNCE($pkt)");
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

    my $completeButCommonSeemsOlder =
        defined($finfo) 
        && defined($finfo->{seqno})
        && $finfo->{checksum} ne $checksum
        && defined($finfo->{innerTimestamp})
        && $finfo->{innerTimestamp} < $timestamp;

    ## Create in pending if absent from common and pending
    ## or allegedly obsolete in common
    my $pendingref = getSubdirModel($pendingSubdir);
    my $pfinfo = $pendingref->{$filename};
    if ($completeButCommonSeemsOlder ||
        (!defined($finfo) && !defined($pfinfo))) {

        # Set up fresh pending if no pf info or older ts
        if (!defined($pfinfo) || $pfinfo->{innerTimestamp} < $timestamp) {
            DPSTD("INITPENDING(fn=$filename,ts=$timestamp,dir=$dir)");
            $pfinfo = newFinfoBare($filename);
            $pfinfo->{subdir} = $pendingSubdir;
            $pfinfo->{length} = $contentLength;
            $pfinfo->{checksum} = $checksum;
            $pfinfo->{innerTimestamp} = $timestamp;
            $pfinfo->{currentLength} = 0;
            $pfinfo->{checkedLength} = 0;
            refreshProvider($pfinfo,$dir,$seqno);
            touchFile("$pendingPath/$filename");
            $pendingref->{$filename} = $pfinfo;
        }

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
        my $existingTimestamp = $finfo->{innerTimestamp};
        return unless defined($existingTimestamp);

        # Ignore older announcments
        return if $finfo->{innerTimestamp} > $timestamp;

        # We've heard about something allegedly newer than what we have
        # We don't actually think this case should happen anymore, so complain
        print STDERR "COMMON CHECKSUM MISMATCH UNIMPLEMENTED, IGNORED $filename\n";
        return;
    }

    ## Complete but mismatch in pending
    if (defined($pfinfo) 
        && defined($pfinfo->{seqno})
        && $pfinfo->{checksum} ne $checksum) {
        print STDERR "PENDING CHECKSUM MISMATCH UNIMPLEMENTED, IGNORED $filename\n";
        return;
    }
}

sub processFileAnnouncement {
    my $bref = shift;
    my $dir = ord($bref->[0])&0x7;
    # [0:2] known to be CDM F type
    my $lenPos = 3;
    my ($filename, $contentLength, $checksum, $timestamp, $seqno);
    ($filename,$lenPos) = getLenArgFrom($lenPos,$bref);
    ($contentLength,$lenPos) = getLenArgFrom($lenPos,$bref);
    ($checksum,$lenPos) = getLenArgFrom($lenPos,$bref);
    ($timestamp,$lenPos) = getLenArgFrom($lenPos,$bref);
    ($seqno,$lenPos) = getLenArgFrom($lenPos,$bref);
    if (scalar(@{$bref}) != $lenPos) {
        DPSTD("Expected $lenPos bytes got ".scalar(@{$bref}));
    }
    DPPKT("AF(fn=$filename,dir=$dir,ts=$timestamp,seq=$seqno)");
    checkAnnouncedFile($filename,$contentLength,$checksum,$timestamp,$seqno,$dir);
}

sub processChunkRequest {
    my $bref = shift;
    my $dir = ord($bref->[0])&0x7;
    # [0:2] known to be CDM C type
    my $lenPos = 3;
    my ($sku, $startingIndex);
    ($sku,$lenPos) = getLenArgFrom($lenPos,$bref);
    ($startingIndex,$lenPos) = getLenArgFrom($lenPos,$bref);
    my $finfo = checkSKUInDir($sku,8);
    if (!defined($finfo)) {
        sendChunkDeniedTo($dir,$sku);
        return;
    }
    my $filename = $finfo->{filename};
    DPPKT("CR(sku=$sku,fn=$filename,si=$startingIndex)");
    sendCommonChunkTo($finfo,$dir,$sku,$startingIndex);
}

my $MAX_D_TYPE_PACKET_LENGTH = 200;
my $dataChunkCode = "D";

sub processDataReply {
    my $bref = shift;
    my $dir = ord($bref->[0])&0x7;
    # [0:2] known to be CDM D type
    my $lenPos = 3;
    my ($sku, $startingIndex);
    ($sku,$lenPos) = getLenArgFrom($lenPos,$bref);
    my $oldLenPos = $lenPos;
    ($startingIndex,$lenPos) = getLenArgFrom($lenPos,$bref);
    if ($oldLenPos + 1 == $lenPos) {
        DPVRB("SKU '$sku' rejected by $dir");
        dropProviderForSKU($dir,$sku);
        return;
    }
    my $finfo = checkSKUInDir($sku,$dir);
    if (!defined($finfo)) {
        DPSTD("WE ARE NOT WAITING FOR '$sku'");
        return;
    }
    my $curlen = $finfo->{currentLength};
    if ($curlen != $startingIndex) {
        if ($curlen > $startingIndex) {
            issueContentRequest($finfo); # try to jump ahead and resync
        } else {
            DPSTD("WE WANT $curlen NOT $startingIndex FROM $sku");
        }
        return;
    }
    my ($data,$hack16);
    ($data,$lenPos) = getLenArgFrom($lenPos,$bref);
    ($hack16,$lenPos) = getLenArgFrom($lenPos,$bref);
    my $check16 = hack16($data);
    if ($hack16 ne $check16) {
        DPSTD("CHECKSUM FAILURE DROPPING PACKET");
        return;
    }
    DPSTD("From ".getDirName($dir).": Starting receive of ".$finfo->{filename})
        if $startingIndex == 0;
    writeDataToPendingFile($finfo, $startingIndex, $data);
    if ($finfo->{currentLength} < $finfo->{length}) {  # We still want more
        issueContentRequest($finfo); # so go ahead ask for more
        my $rateLimiterUsec = 62_500; # But no more than 16Hz
        Time::HiRes::usleep($rateLimiterUsec);
    } else {
        DPSTD("From ".getDirName($dir).": Received last of ".$finfo->{filename});
    }
}

sub sendChunkDeniedTo {
    my ($dir, $sku) = @_;

    my $pkt = chr(0x80+$dir).chr($CDM_PKT_TYPE).$dataChunkCode;
    $pkt = addLenArgTo($pkt,$sku);
    $pkt .= chr(0);
    DPPKT("DENIED($pkt)");
    writePacket($pkt);
}

sub sendCommonChunkTo {
    my ($finfo, $dir, $sku, $startingIndex) = @_;
    defined $startingIndex or die;
    my $length = $finfo->{length};
    my $maxWanted = $length - $startingIndex;
    $maxWanted = 0 if $maxWanted < 0;

    my $pkt = chr(0x80+$dir).chr($CDM_PKT_TYPE).$dataChunkCode;
    $pkt = addLenArgTo($pkt,$sku);
    $pkt = addLenArgTo($pkt,$startingIndex);

    my $maxRemaining = 
        $MAX_D_TYPE_PACKET_LENGTH # Max size
        - length($pkt)            # Currently used
        - 1                       # for length of data
        - 3                       # for 2+hack16 'checksum'
        ;

    my $innerTimestamp = $finfo->{innerTimestamp};
    DPSTD("To ".getDirName($dir)." Starting to send ".$finfo->{filename}." ($innerTimestamp:$sku)") 
        if $startingIndex==0;
    if ($maxWanted > $maxRemaining) {
        $maxWanted = $maxRemaining;
    } else {
        DPSTD("To ".getDirName($dir).": Sending last of ".$finfo->{filename}." ($innerTimestamp:$sku)");
    }
    my $data = getDataFromCommonFile($finfo, $startingIndex, $maxWanted);
    my $hack16 = hack16($data);
    $pkt = addLenArgTo($pkt,$data);
    $pkt = addLenArgTo($pkt,$hack16);
    DPPKT("DATA: $maxWanted bytes at $startingIndex to $sku for ".getDirName($dir));
    writePacket($pkt);
}

sub writeDataToPendingFile {
    my ($finfo, $startingIndex, $data) = @_;
    my $filename = $finfo->{filename};
    my $path = "$baseDir/pending/$filename";
    open my $fh,'+<',$path or die "Can't update $path: $!";
    sysseek $fh, $startingIndex, 0 or die "Can't seek $path to $startingIndex: $!";
    my $writeLen = length($data);
    my $wrote = syswrite $fh, $data, $writeLen;
    if ($wrote != $writeLen) {
        DPSTD("Wanted to write $writeLen at $startingIndex of $filename, but only wrote $wrote");
        return;
    }
    close $fh or die "Can't close $path: $!";
    $finfo->{currentLength} += $writeLen;
    DPVRB("WROTE $writeLen to $startingIndex of $path");
}

sub getDataFromCommonFile {
    my ($finfo, $startingIndex, $maxWanted) = @_;
    my $filename = $finfo->{filename};
    my $path = "$baseDir/common/$filename";
    open my $fh,'<',$path or die "Can't read $path: $!";
    sysseek $fh, $startingIndex, 0 or die "Can't seek $path to $startingIndex: $!";
    my $data;
    my $read = sysread $fh, $data, $maxWanted;
    if ($read != $maxWanted) {
        DPSTD("Wanted $maxWanted at $startingIndex of $filename, but got $read");
    }
    close $fh or die "Can't close $path: $!";
    return $data;
}

sub hack16 {
    my $str = shift;
    my $h = 0xfeed;
    for my $i (0 .. (length ($str) - 1)) {
        $h = (($h<<1)^ord(substr($str,$i,1))^($h>>11))&0xffff;
    }
    return chr(($h>>8)&0xff).chr($h&0xff);
}

sub declareNgbDirAlive {
    my $srcDir = shift;
    my $ngb = getNgbInDir($srcDir);
    $ngb->{clacksSinceAliveRcvd} = 0;
    if (!$ngb->{isAlive}) {
        $ngb->{isAlive} = 1;
        DPSTD(getDirName($srcDir)." is alive");
    }
}

sub processPacket {
    my $pkt = shift;
    if (length($pkt) < 3) {
        DPSTD("Short packet '$pkt' ignored");
        return;
    }
    my @bytes = split(//,$pkt);
    my $byte0 = ord($bytes[0]);

    if ($byte0&0x08) {
        print "Packet error reported on '$pkt'\n";
    }
    my $srcDir = $byte0&0x07;
    if ($bytes[1] eq $CDM_PKT_TYPE_BYTE) {
        declareNgbDirAlive($srcDir);

        if ($bytes[2] eq "A") {
            # Handle old len3 type A packets
            DPPKT(sprintf("Rcvd 'A' from %d uniq %02x\n",$srcDir,defined($bytes[3]) ? ord($bytes[3]) : 0));
            return;
        }
        if ($bytes[2] eq "F") {
            processFileAnnouncement(\@bytes);
            return;
        }
        if ($bytes[2] eq "C") {
            processChunkRequest(\@bytes);
            return;
        }
        if ($bytes[2] eq "D") {
            processDataReply(\@bytes);
            return;
        }
    }
    DPSTD("UNHANDLED PKT($pkt)");
}

# current time in TWO-SECOND increments
sub now {
    return time()>>1;
}

my $userButtonLastKnownState;
my $userButtonDevice = "/sys/bus/iio/devices/iio:device0/in_voltage5_raw";
sub readButtonState {
    open BUT, "<", $userButtonDevice or return 0; # Silently say no button press if no device
    my $val = <BUT>;
    close BUT or die "close $userButtonDevice: $!";
    chomp $val;
    my $buttonPressed = ($val < 2000) ? 1 : 0;
    return $buttonPressed;
}
    
sub checkUserButton {
    my $buttonPressed = readButtonState();
    # Require three matching readings for debounce
    return 0 
        if $buttonPressed != readButtonState() 
        or $buttonPressed != readButtonState();

    my $userButtonPressDetected = 0;
    if (defined($userButtonLastKnownState) && !$userButtonLastKnownState && $buttonPressed) {
        $userButtonPressDetected = 1;
    }
    $userButtonLastKnownState = $buttonPressed;
    return $userButtonPressDetected;
}

my $statPID;
#my $statProgPath = "/home/t2/GITHUB/GFB/T2-GFB/stat13.pl";
#my $statProgPath = "/home/t2/T2-12/apps/cdm/runStat.sh";
my $statProgPath = "/home/t2/GITHUB/MFM/bin/t2viz";
my $statProgName = "t2viz";
my $statProgHelper = "/home/t2/T2-12/apps/mfm/RUN_SDL";

sub checkForStat {
    my $ps = `ps wwwu -C $statProgName`;
    my @lines = grep { m!^root\s+(\d+)\s+[^\n]+$statProgPath$! } split(/\n+/,$ps);
    my $count = scalar(@lines);
    if ($count == 0) {
        $statPID = undef;
        print STDERR "NO STATPID FOUND\n";
        return;
    }
    if ($count > 1) {
        print STDERR "WARNING: MULTIPLE STAT MATCHES:\n".join(" \n",@lines)."\n";
    }
    my @fields = split(/\s+/,$lines[0]);
    $statPID = $fields[1];
    print STDERR "FOUND STATPID ($statPID)\n";
}

sub controlStatProg {
    my $statsRunning = shift;
    checkForStat();
    if (!$statsRunning) {
        if (defined $statPID) { 
            my $kilt = kill 'INT', $statPID;
            print "Killed $statPID ($kilt)\n";
        } else {
            print "No statpid?\n";
        }
        $statPID = undef;
    } else {
        system("nohup $statProgHelper $statProgPath &") unless defined $statPID;
    }
    sleep 1;
}

sub toggleDebugPanel {
    $debugPanelShouldBeDisplayed = $debugPanelShouldBeDisplayed ? 0 : 1;
    controlStatProg($debugPanelShouldBeDisplayed);
    print "TGOPANEL($debugPanelShouldBeDisplayed)\n";
}

sub eventLoop {
    my $lastBack = now();
    my $incru = 10000;
    my $minu = 10000;
    my $maxu = 500000;
    my $usleep = $minu;
    while ($continueEventLoop) {
        my $sleep = 1;
        if (checkUserButton()) {
            toggleDebugPanel();
        }
        if (my $packet = readPacket()) {
            processPacket($packet);
            $usleep = $minu;
            $sleep = 0;
        }
        if ($lastBack != now()) {
            doBackgroundWork();
            $lastBack = now();
            $sleep = 0;
        }
        if ($sleep) {
            Time::HiRes::usleep($usleep);
            if ($usleep < $maxu) {
                $usleep += $incru; 
            }
        }
    }
}

sub main {
    STDOUT->autoflush(1);
    flushPendingDir();
    checkInitDirs();
    preinitCommon();
    openPackets();
    flushPackets();
    eventLoop();
    closePackets();
}

if (scalar(@ARGV)) {
    my $ok = 1;
    foreach my $arg (@ARGV) {
        my $base = basename($arg);
        if ($base !~ /.*?[.]mfz$/) {
            print "Not .mfz '$arg'\n";
            $ok = 0;
        } elsif (!-r $arg) {
            $ok = 0;
            print "Unreadable '$arg'\n";
        } 
    }
    exit 1 unless $ok;
    my $destdir = "/cdm/common";
    foreach my $arg (@ARGV) {
        if (!copy($arg,$destdir)) {
            print "Copy $arg-> $destdir failed: $!";
            $ok = 0;
        } else {
            print "$arg -> $destdir\n";
        }
    }
    exit 2 unless $ok;
    checkInitDirs();
    preinitCommon();
    exit 0;
} else {
    print "STARTING STANDARD\n";
    main();
    exit 9;
}


