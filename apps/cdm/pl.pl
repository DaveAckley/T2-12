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

use constant CDM_PROTOCOL_VERSION_PIPELINE => 2;    # 202008140223 Pipeline overlay
use constant CDM_PROTOCOL_VERSION_ASPINNER => 1;    # Pre-version-protocol version
use constant CDM_PROTOCOL_VERSION_PREHISTORY => 0;  
use constant CDM_PROTOCOL_VERSION_UNKNOWN => -1;  

###########
my $CDM_PROTOCOL_OUR_VERSION = CDM_PROTOCOL_VERSION_PIPELINE;
###########

my $PIPELINE_ENABLED = 1;
my $CDM_PKT_BULK_FLAG = 0x80;
my $CDM_PKT_CDM_CMD = 0x03; # was ^C for CDM.  
my $CDM_PKT_TYPE = $CDM_PKT_BULK_FLAG | $CDM_PKT_CDM_CMD; # Now it's 0x83 for 'no break here'??
my $CDM_PKT_TYPE_BYTE = chr($CDM_PKT_TYPE);

my $MAX_MFZ_NAME_LENGTH = 28+4; # 4 for '.mfz'

my $pktdev = "/dev/itc/bulk";
my $mode = O_RDWR|O_NONBLOCK;

my @dirnames = ("NT", "NE", "ET", "SE", "ST", "SW", "WT", "NW");

use constant DEBUG_FLAG_PACKETS => 1;
use constant DEBUG_FLAG_DEBUG => DEBUG_FLAG_PACKETS<<1;
use constant DEBUG_FLAG_STANDARD => DEBUG_FLAG_DEBUG<<1;
use constant DEBUG_FLAG_VERBOSE => DEBUG_FLAG_STANDARD<<1;
use constant DEBUG_FLAG_ALL => 0xffffffff;

my $DEBUG_FLAGS = DEBUG_FLAG_STANDARD; ## = DEBUG_FLAG_ALL

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
    'cdmd-MFM.mfz' => "/home/t2",
#DEPRECATED    'cdmd-MFM.mfz' => "/home/t2/GITHUB",
    'cdmd-T2-12.mfz' => "/home/t2",
#DEPRECATED    'cdmd-T2-GFB.mfz' => "/home/t2/GITHUB/GFB",
#DEPRECATED    'cdmd-t2.mfz' => "/home",
    );

sub DPF {
    my ($flags,$msg) = @_;
    return unless $DEBUG_FLAGS & $flags;
    print "$msg\n";
}

sub DPPKT { DPF(DEBUG_FLAG_PACKETS,shift); }
sub DPSTD { DPF(DEBUG_FLAG_STANDARD,shift); }
sub DPVRB { DPF(DEBUG_FLAG_VERBOSE,shift); }
sub DPDBG { DPF(DEBUG_FLAG_DEBUG,shift); }

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
        DPPKT("GOT PACKET[$count]($pkt)");
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
        Time::HiRes::usleep($usec += 10000);
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

#my $baseDir = "./cdmDEBUG";
my $baseDir = "/cdm";
my $commonSubdir = "common";
my $pendingSubdir = "pending";
my $logSubdir = "log";
my $pubkeySubdir = "public_keys";
my $pipelineSubdir = "pipeline";
my @subDirs = ($commonSubdir, $pendingSubdir,$logSubdir,$pubkeySubdir,$pipelineSubdir);
my $commonPath = "$baseDir/$commonSubdir";
my $pendingPath = "$baseDir/$pendingSubdir";
my $pipelinePath = "$baseDir/$pipelineSubdir";

my $mfzrunProgPath = "/home/t2/MFM/bin/mfzrun";

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

    my $path = getFinfoPath($finfo);
    # 'echo Q' below is needed if there's a problem with
    # /cdm/public_keys (or with the signature of $path), but we don't
    # want the subprocess to hang on input ever if we can avoid it
    my $cmd = "echo Q | $mfzrunProgPath -kd /cdm $path VERIFY";
    my $output = `$cmd`;

    if ($output =~ /.*?signer handle '(:?[a-zA-Z][-., a-zA-Z0-9]{0,62})' is not recognized!/) {
        my $badhandle = $1;
        DPSTD("Unrecognized handle '$badhandle' in $path");
        return 0;
    }

    if ($output !~ s/^SIGNING_HANDLE \[(:?[a-zA-Z][-., a-zA-Z0-9]{0,62})\]//m) {
        DPSTD("Handle of $path not found in '$output'");
        return 0;
    }
    my $handle = $1;

    if ($output !~ s/^INNER_TIMESTAMP \[(\d+)\]//m) {
        DPSTD("Timestamp of $path not found in '$output'");
        return 0;
    }
    my $timestamp = $1;

    # my $strp = DateTime::Format::Strptime->new(
    #     pattern   => '%a %b %e %H:%M:%S %Y',
    #     );
    # my $dt = $strp->parse_datetime( $timestamp );
    # my $epoch = $dt->strftime("%s");
    DPSTD(" $path: $handle => $timestamp");

    $finfo->{signingHandle} = $handle;
    $finfo->{innerTimestamp} = $timestamp;
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

sub installCDMDGFB {
    my ($finfo) = @_;
    installCDMD($finfo);
 # Nothing special needed anymore
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
    return unless runCmdWithSync("make -C /home/t2/T2-12 -k install","T2-12: make install: ERROR");
    print "REBOOTING!\n";
    runCmdWithSync("reboot","reboot: ERROR");
}

sub installCDMDMFM {
    return unless defined installCDMD(@_);
    my $mfmt2pid = `ps -C mfmt2 -o pid=`;
    chomp $mfmt2pid;
    if ($mfmt2pid =~ /^\s*[0-9]+$/) {
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

    my $plinfo = plSetupCommonFile($finfo); # Something changed on this guy

    my $count = 0;
    foreach my $k (shuffle(keys %hoodModel)) {
        my $v = $hoodModel{$k};
        if ($v->{isAlive}) {
            if ($v->{cdmProtocolVersion} >= CDM_PROTOCOL_VERSION_PIPELINE) {
                plAnnounceFileTo($v,$plinfo);
            } elsif ($v->{cdmProtocolVersion} > CDM_PROTOCOL_VERSION_UNKNOWN) {
                # Don't announce til they give us a version 
                announceFileTo($v,$finfo);
            }
            ++$count;
        }
    }
    DPPKT("ANNOUNCED $filename to $count");
}

sub assignSeqnoAndCaptureModtime {
    my ($finfo,$newpath) = @_;
    my $filename = $finfo->{filename} or die;
    my $seqno = assignSeqnoForFilename($filename);
    $finfo->{seqno} = $seqno;
    $finfo->{modtime} = -M $newpath;
    return $seqno;
}

sub checkAndReleasePendingFileAndAnnounce {
    my $finfo = shift or die;
    checkAndReleasePendingFile($finfo);
    checkTriggersAndAnnounce($finfo);
}

sub checkAndReleasePendingFile {
    my $finfo = shift or die;
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
    my $seqno = assignSeqnoAndCaptureModtime($finfo,$newpath);
    DPDBG("checkAndReleasePendingFile MFZ modtime ".$finfo->{modtime});

    delete $pref->{$filename}; # Remove metadata from pending
    $cref->{$filename} = $finfo; # Add it to common
    DPSTD("RELEASED $filename");

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
    return generateSKUFromParts($finfo->{filename},$finfo->{checksum},$finfo->{innerTimestamp},$seqno);
}

sub generateSKUFromParts {
    my ($filename, $checksum, $timestamp, $seqno) = @_;
    my $sku = sprintf("%s%02x%02x%03d%s",
                      substr($filename,0,1),
                      ord(substr($checksum,0,1)),
                      ord(substr($checksum,1,1)),
                      $timestamp%1000,
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
        checkAndReleasePendingFileAndAnnounce($finfo);
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
            my $ngbversion = $ngb->{cdmProtocolVersion};
            announceFileTo($ngb,$finfo)
                if $ngbversion > CDM_PROTOCOL_VERSION_UNKNOWN  # Don't announce til they give us a version
                && $ngbversion < CDM_PROTOCOL_VERSION_PIPELINE; # Don't be traditional if pipeline will do
            ++$announcements;
            last if oneIn(2);
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
        cdmProtocolVersion => -1, # No version information received
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
        $ngb->{cdmProtocolVersion} = -1;  # Back to unknown
        DPSTD(getDirName($ngb->{dir})." is dead");
    }
    
    if (rand(++$ngb->{clacksSinceAliveSent}) > 5) {
#           print STDERR " ALV".$ngb->{dir}."\n";

        $ngb->{clacksSinceAliveSent} = 0;
        $alivetag = ($alivetag + 1)&0xff;
        sendCDMTo($ngb->{dir},'A',chr($alivetag).chr($CDM_PROTOCOL_OUR_VERSION));
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

    # PIPELINE MGMT
    plDoBackgroundWork();
}

sub createAnnounceFilePacket {
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
    return $pkt;
}

sub announceFileTo {
    my ($aliveNgb,$finfo) = @_;
    $pkt = createAnnounceFilePacket($aliveNgb,$finfo);
    writePacket($pkt);
}

sub touchFile {
    my $path = shift;
    open TMP, ">", $path or die "Can't touch $path: $!";
    close TMP or die "Can't close touched $path: $!";
}

sub checkIfFileInCommon {
    my ($filename,$checksum,$timestamp) = @_;

    ## Ignore complete and matched in common
    my $commonref = getSubdirModel($commonSubdir);
    my $finfo = $commonref->{$filename};
    return 1 if # ignore announcement if the file
        defined $finfo               # exists
        && defined $finfo->{seqno}   # and is complete
        && $finfo->{checksum} eq $checksum;  # and matches
    return 1 if # also ignore announcement if the file
        defined $finfo               # exists
        && !defined $finfo->{seqno}; # but isn't complete
    return 0;
}

sub checkAnnouncedFile {
    my ($filename,$contentLength,$checksum,$timestamp,$seqno,$dir) = @_;
    die unless defined $dir;

    DPDBG("CHECKING Ignore complete and matched in common");
    return if checkIfFileInCommon($filename,$checksum,$timestamp);
        
    my $commonref = getSubdirModel($commonSubdir);
    my $finfo = $commonref->{$filename};

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

sub plsReadFile {
    my ($plinfo, $filepos, $length) = @_;
    my $path = $plinfo->{filePath};
    open HDL, "<", $path or die "plsReadFile $path: $!";
    seek HDL, $filepos, Fcntl::SEEK_SET;
    my $data = "";
    my $count = read HDL,$data,$length;
    if (!defined $count) {
        DPSTD("UNEXPECTED EOF AT $path+$filepos");
    }
    close HDL or die "Can't close $path: $!";
    return $data;
}

sub plsCheckXsumStatus {
    my ($plinfo,$xsumopt) = @_;
    my $dig = $plinfo->{xsumDigester}->clone->b64digest();
    return $dig eq $xsumopt;
}

sub plsGetFileActualLength {
    my $plinfo = shift or die;
    my $path = $plinfo->{filePath};
    my $len = -s $path;
    return $len;
}

sub plsWriteChunk {
    my ($plinfo, $chunk, $atpos) = @_;
    die unless defined $atpos;
    my $path = $plinfo->{filePath};
    open HDL, ">>", $path or die "plsWriteChunk $path: $!";
    my $filepos = tell HDL;
    if ($atpos != $filepos) {
        DPSTD("Ignoring out of sequence chunk at $atpos; file at $filepos")
            if $atpos+length($chunk) != $filepos; # Be quiet about immediate redundancies
        return undef;
    }
    print HDL $chunk;
    $filepos = tell HDL; # update
    close HDL or die "Can't close $path: $!";
    $plinfo->{xsumDigester}->add($chunk);
    return $filepos;
}

sub plsGetChunkAt {
    my ($plinfo, $filepos) = @_;
    my $chunkLen = 180;
    my ($markpos, $xsum) = plsFindXsumInRange($plinfo, $filepos, $filepos+$chunkLen);
    if (defined $xsum) {
        if ($markpos > $filepos) {
            $xsum = undef; # Don't return xsum til it's first in chunk
            $chunkLen = $markpos - $filepos;   # but change length so that it will be first next time
        }
    } 
    my $chunk = plsReadFile($plinfo, $filepos, $chunkLen);
    return ($chunk, $xsum);
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

sub processAlivePacket {
    my $bref = shift or die;
    my @bytes = @$bref;
    my $pktlen = scalar(@bytes); # pktlen known >= 3
    my $srcDir = ord($bytes[0])&0x07;
    my $ngb = getNgbInDir($srcDir);
    my $ngbversion = $pktlen < 5 ? 1 : ord($bytes[4]);

    if ($ngb->{cdmProtocolVersion} != $ngbversion) {
        DPSTD(getDirName($srcDir)." RUNNING VERSION $ngbversion");
        $ngb->{cdmProtocolVersion} = $ngbversion;
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

        if ($bytes[2] eq "P" && $PIPELINE_ENABLED) {
            plProcessPacket(\@bytes);
            return;
        }

        if ($bytes[2] eq "A") {
            processAlivePacket(\@bytes);
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

my $statPID;
my $statProgPath = "/home/t2/MFM/bin/t2viz";
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

#### NOT USED BUT CURRENTLY KEPT AS SAMPLE CODE
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

sub eventLoop {
    my $lastBack = now();
    my $incru = 10000;
    my $minu = 10000;
    my $maxu = 500000;
    my $usleep = $minu;
    while ($continueEventLoop) {
        my $sleep = 1;
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

#####################
### PIPELINE IMPLEMENTATION
use Data::Dumper;
$Data::Dumper::Sortkeys = 1;
my %plFILEtoPLINFO;         # filename -> plinfo
my %plOUTBOUNDTAGtoPLINFO;  # outboundTag -> plinfo
my %plFILEtoPROVIDER; # filename -> {dir -> "PREC"[dir inboundtag prefix sage rage ..] }
use constant PREC_PDIR => 0;
use constant PREC_ITAG => 1;
use constant PREC_PFXL => 2;
use constant PREC_SAGE => 3;
use constant PREC_RAGE => 4;
my %plPROVIDERtoFILE; # dir -> {tag -> filename}

my $plSPINNER = int(rand(256)); # init 0..255

sub plNextSpinnerValue { 
    $plSPINNER = 1 if ++$plSPINNER >= 128;  # SKIPS ZERO AND 128..255
    return $plSPINNER;
}

sub plNewTag {
    my $spin = plNextSpinnerValue();
    my $rnd = int(rand(1<<24));
    return ($spin<<24)|$rnd;
}

sub plAddTagTo {
    my ($str,$tag) = @_;
    die("Undefined or zero tag supplied at '$str'") unless defined $tag && $tag != 0;
    my $netorder = pack("N",$tag); # Bigendian
    $str .= $netorder;
    return $str;
}

sub plGetTagArgFrom {
    my ($lenpos,$bref) = @_;
    return (0, $lenpos) if (scalar(@{$bref})) < $lenpos+4;
    my $repack = pack("C4",map(ord,@$bref[$lenpos..($lenpos+4-1)]));
    my $tag = unpack("N",$repack);
    return ($tag, $lenpos+4);
}

sub plInitTagsAndProviders {
    return unless $PIPELINE_ENABLED;
    %plFILEtoPROVIDER = ();
    %plPROVIDERtoFILE = ();
}

sub plPreinitCommonFiles {
    return unless $PIPELINE_ENABLED;
    DPSTD("PREINIT COMMON FILE PIPELINES");
    my $cref = getSubdirModel($commonSubdir);
    my $deaders = 0;
    my @finfos = values %{$cref};
    foreach my $finfo (@finfos) {
        plSetupCommonFile($finfo);
    }
}

sub plGetFilenameFromInboundTag {
    my ($tag,$dir) = @_;
    defined $dir or die;
    my $tagmap = $plPROVIDERtoFILE{$dir};
    return undef unless defined $tagmap;
    return $tagmap->{$tag};
}

sub plGetPlinfoFromInboundTag {
    my ($tag,$dir) = @_;
    defined $dir or die;
    my $filename = plGetFilenameFromInboundTag($tag,$dir);
    return undef unless defined $filename;
#    print "plP2FZZ ".Dumper(\%plPROVIDERtoFILE);
#    print "plF2PZZ ".Dumper(\%plFILEtoPROVIDER);

    return plFindPLS($filename);
}

sub plPutFilenameOnInboundTag {
    my ($tag,$dir,$filename) = @_;
    defined $filename or die;
    my $tagmap = $plPROVIDERtoFILE{$dir};
    if (!defined $tagmap) {
        $tagmap = {};
        $plPROVIDERtoFILE{$dir} = $tagmap;
    }
    $tagmap->{$tag} = $filename;
}

sub plPutOnInboundTag {
    my ($tag,$dir,$plinfo) = @_;
    defined $plinfo or die;
    my $filename = $plinfo->{fileName};
    defined $filename or die;
    plPutFilenameOnInboundTag($tag,$dir,$filename);
}

sub plFindPLS {
    my $name = shift or die;
    my $plinfo = $plFILEtoPLINFO{$name};
    return $plinfo;
}

sub plFindPLSFromOutboundTag {
    my $obtag = shift or die;
    my $plinfo = $plOUTBOUNDTAGtoPLINFO{$obtag};
    return $plinfo;
}


sub plPathFromName {
    my $name = shift or die;
    return "$pipelinePath/$name";
}

sub plNewPLS {
    my $name = shift or die;
    my $path = plPathFromName($name);

    my %ret = (
        finfo => undef,
        fileName => $name,
        filePath => undef,
        fileLength => -1,
        fileInnerTimestamp => -1,
        fileChecksum => "",
        prefixLengthAvailable => 0,
        xsumMap => [],
        xsumDigester => Digest::SHA->new(256),
        outboundTag => 0
        );
    
    return \%ret;
}

# Call at startup
sub plFlushPipelineDir {
    my $count = remove_tree($pipelinePath);
    if ($count > 1) {
        DPSTD("Flushed $count $pipelinePath files");
    }
    %plFILEtoPLINFO = ();
}

sub plCreateChunkRequestPacket {
    my ($dir,$filename,$filepos) = @_;
    my $prec = plGetProviderRecordForFilenameAndDir($filename,$dir);
    my ($precdir,$tag,$pfx,$sage,$rage) = @{$prec};
    die unless $dir == $precdir;
    $prec->[PREC_SAGE] = now(); # [3] sage is last time we sent a request
    DPDBG("PRECQ plCreateChunkRequestPacket($filename,$filepos,$precdir,$tag,$pfx,$sage,$rage)");
    return undef if $filepos > $pfx;
    my $pipelineOperationsCode = "P";
    my $chunkRequestCode = "R";
    my $pkt = chr(0x80+$dir).chr($CDM_PKT_TYPE).$pipelineOperationsCode.$chunkRequestCode;
    $pkt = plAddTagTo($pkt,$tag);
    $pkt = addLenArgTo($pkt,$filepos);
    return $pkt;
}

sub plCreatePipelinePrefixAvailabilityPacket {
    my ($aliveNgb,$plinfo) = @_;
    die unless defined $plinfo->{outboundTag};
    my $pipelineOperationsCode = "P";
    my $fileAnnouncementCode = "A";
    my $pkt = chr(0x80+$aliveNgb->{dir}).chr($CDM_PKT_TYPE).$pipelineOperationsCode.$fileAnnouncementCode;
    $pkt = plAddTagTo($pkt,$plinfo->{outboundTag});
    $pkt = addLenArgTo($pkt,$plinfo->{prefixLengthAvailable});
    DPPKT("PIPELINEPREFIXAVAIL($pkt)");
    return $pkt;
}

sub plCreatePipelineFileAnnouncementPacket {
    my ($aliveNgb,$plinfo) = @_;
#    print STDERR " ANCE".$aliveNgb->{dir}.": ".$finfo->{filename}."+".$finfo->{innerTimestamp}."\n";

    die unless defined $plinfo->{outboundTag};
    my $pipelineOperationsCode = "P";
    my $fileAnnouncementCode = "F";
    my $pkt = chr(0x80+$aliveNgb->{dir}).chr($CDM_PKT_TYPE).$pipelineOperationsCode.$fileAnnouncementCode;
    $pkt = plAddTagTo($pkt,$plinfo->{outboundTag});
    $pkt = addLenArgTo($pkt,$plinfo->{fileName});
    $pkt = addLenArgTo($pkt,$plinfo->{fileLength});
    $pkt = addLenArgTo($pkt,$plinfo->{fileInnerTimestamp});
    $pkt = addLenArgTo($pkt,$plinfo->{fileChecksum});
#    DPPKT("PIPELINEANNOUNCE($pkt)");
    return $pkt;
}

sub plAnnounceFileTo {
    my ($ngb,$plinfo) = @_;
    defined $plinfo or die;
    my $pkt = plCreatePipelineFileAnnouncementPacket($ngb,$plinfo);
    writePacket($pkt);
    my $availpacket = plCreatePipelinePrefixAvailabilityPacket($ngb,$plinfo);
    writePacket($availpacket);
    DPPKT("ANNOUNCED PIPELINE $plinfo->{outboundTag} => $plinfo->{filePath} TO $ngb->{dir}");
}
    

sub plDoBackgroundWork {
    return unless $PIPELINE_ENABLED;
    my $ngb = getRandomAliveNgb();
    return unless
        defined $ngb &&
        $ngb->{cdmProtocolVersion} >= CDM_PROTOCOL_VERSION_PIPELINE;

    if (oneIn(2)) {
        # outbound work
        my @otags = keys %plOUTBOUNDTAGtoPLINFO;
        my $otag = $otags[createInt(scalar(@otags))];
        my $plinfo = plFindPLSFromOutboundTag($otag);
        defined $plinfo or die;
        plAnnounceFileTo($ngb,$plinfo)
            if $plinfo->{prefixLengthAvailable} > 0;
    } else {
        # inbound work
        my @filenames = keys %plFILEtoPLINFO;
        my $filecount = scalar(@filenames);
        if ($filecount > 0) {
            my $filename = $filenames[createInt($filecount)];
            my $plinfo = plFindPLS($filename);
            plsMaybeSendChunkRequest($plinfo,$ngb->{dir})
                if defined $plinfo;
        }
    }
}

sub plSetupCommonFile {
    my $finfo = shift or die;
    my $name = $finfo->{filename};
    $finfo->{checkedLength} == $finfo->{length} or die;
    if (defined (plFindPLS($name))) {
        DPSTD("PLS exists for '$name', regenerating");
    }

    my $path = getFinfoPath($finfo);
    my $plinfo = plNewPLS($name);
    $plinfo->{finfo} = $finfo;
    $plinfo->{filePath} = $path;
    $plinfo->{fileChecksum} = $finfo->{checksum};
    $plinfo->{fileLength} = $finfo->{length};
    $plinfo->{prefixLengthAvailable} = $finfo->{length};
    $plinfo->{fileInnerTimestamp} = $finfo->{innerTimestamp};
    $plinfo->{outboundTag} = plNewTag();
    plsBuildXsumMap($plinfo);
    plSetPlinfoAsSource($plinfo);
    DPSTD(" pipeline initted: $name => $plinfo->{outboundTag}");
    return $plinfo;
}

## For use with both common/ and pipeline/ files
sub plSetPlinfoAsSource {
    my $plinfo = shift or die;
    my $name = $plinfo->{fileName};
    my $otag = $plinfo->{outboundTag};
    die unless defined $name && defined $otag && $otag > 0;

    if (defined $plFILEtoPLINFO{$name}) {
        DPSTD("Reinitting $name");
        delete $plFILEtoPLINFO{$name};
        delete $plOUTBOUNDTAGtoPLINFO{$otag};
    }

    $plFILEtoPLINFO{$name} = $plinfo;
    $plOUTBOUNDTAGtoPLINFO{$otag} = $plinfo;
}

## For use only with pipeline/ files
sub plSetPlinfoAsSourceAndInit {
    my $plinfo = shift or die;
    plSetPlinfoAsSource($plinfo);

    my $name = $plinfo->{fileName};
    my $plpath = plPathFromName($name);
    my $path = $plinfo->{filePath};
    die unless $plpath eq $path;

    DPSTD("Resetting $path");
    open(HDL,">",$path) or die "Can't write $path to init: $!";
    close HDL or die "Can't close $path after init: $!";

    $plinfo->{prefixLengthAvailable} = 0;

    DPSTD("Initted $path");
    return $plinfo;
}


sub plSetupNewPipelineFile {
    my ($name,$contentLength,$checksum,$timestamp) = @_;
    my $plinfo = plNewPLS($name);
    $plinfo->{finfo} = undef;
    $plinfo->{filePath} = plPathFromName($name);
    $plinfo->{fileChecksum} = $checksum;
    $plinfo->{fileLength} = $contentLength;
    $plinfo->{fileInnerTimestamp} = $timestamp;
    $plinfo->{outboundTag} = plNewTag();

    return $plinfo;
}

sub clacksAge {
    my $oldnow = shift;
    defined $oldnow or die;
    return now() - $oldnow;
}

sub clacksOld {
    my ($prevnow, $clacks) = @_;
    die unless defined $clacks;
    return $prevnow + $clacks <= now();
}

sub plProcessPrefixAvailability {
    my ($dir,$bref) = @_;
    my $blen = scalar(@$bref);
    # [0:3] known to be CDM PA type
    my $lenPos = 4;
    my ($inboundTag,$prefixlen);
    ($inboundTag,$lenPos)  = plGetTagArgFrom($lenPos,$bref);
    ($prefixlen,$lenPos)   = getLenArgFrom($lenPos,$bref);
    $prefixlen += 0; # destringify
    my $plinfo = plGetPlinfoFromInboundTag($inboundTag,$dir);
    if (!defined $plinfo) {
        DPSTD("PA: No plinfo for $inboundTag from $dir, ignoring");
        return;
    }
    my $filename = $plinfo->{fileName};
    my $prec = plGetProviderRecordForFilenameAndDir($filename, $dir);
    die if $prec->[PREC_PDIR] != $dir;
    if ($prec->[PREC_ITAG] != $inboundTag) {
        if ($prec->[PREC_PFXL] != 0) {
            DPSTD("PA: Overwriting old tag '$prec->[PREC_ITAG]' for $filename from $dir with '$inboundTag'");
        }
        $prec->[PREC_ITAG] = $inboundTag;  # set up tag
        $prec->[PREC_PFXL] = -1;
        $prec->[PREC_SAGE] = 0;  # sage refreshes when we send a chunk request
        $prec->[PREC_RAGE] = 0;  # rage refreshes when we recv a chunk reply
    }
    $prec->[PREC_PFXL] = $prefixlen;  # and actual availability

    ### Start the pipeline after we get a prefix, not just an announcement.
    my $commonref = getSubdirModel($commonSubdir);
    my $finfo = $commonref->{$filename};

    my $completeButCommonSeemsOlder =
        defined($finfo) 
        && defined($finfo->{seqno})
        && $finfo->{checksum} ne $plinfo->{fileChecksum}
        && defined($finfo->{innerTimestamp})
        && $finfo->{innerTimestamp} < $plinfo->{fileInnerTimestamp};

    ## Start the pipeline if absent from common and pipeline
    ## or allegedly obsolete in common

    if ($completeButCommonSeemsOlder || !defined($finfo)) {
        plsMaybeSendChunkRequest($plinfo, $dir);
        return;
    }
}

sub plsMaybeSendChunkRequest {
    my ($plinfo,$dir) = @_;
    die unless defined $dir && defined $plinfo;
    my $filename = $plinfo->{fileName};
    my $prec = plGetProviderRecordForFilenameAndDir($filename,$dir);
    my $sage = $prec->[PREC_SAGE];
    if (clacksAge($sage) >= 3) {
        my $len = plsGetFileActualLength($plinfo);
        if ($len < $prec->[PREC_PFXL]) {  # Don't ask for more than they got
            my $filepath = $plinfo->{filePath};
            DPSTD("REQUESTING $filepath:$len FROM $dir:$prec->[PREC_PFXL] AT AGE ".clacksAge($sage));
            my $chunkpacket = plCreateChunkRequestPacket($dir,$filename,$len);
            if (!defined $chunkpacket) {
                DPDBG("NO CHUNKS");
                return;
            }
            $prec->[PREC_SAGE] = now(); # sage refreshes when we send a request
            writePacket($chunkpacket);
        }
    }
}

sub plProcessChunkRequestAndCreateReply {
    my ($dir,$bref) = @_;
    my $blen = scalar(@$bref);
    # [0:3] known to be CDM PR type
    my $lenPos = 4;
    my ($outboundTag,$filepos);
    ($outboundTag,$lenPos) = plGetTagArgFrom($lenPos,$bref);
    ($filepos,$lenPos)    = getLenArgFrom($lenPos,$bref);
    $filepos += 0; # destringify
#    DPSTD("plPCR($outboundTag,$filepos)");
#    print "QQplOUTBOUNDTAGtoPLINFO ".Dumper(\%plOUTBOUNDTAGtoPLINFO);
    my $plinfo = plFindPLSFromOutboundTag($outboundTag);
    if (!defined $plinfo) {
        DPSTD("PR: No plinfo for $outboundTag from $dir, ignoring");
        return undef;
    }
#    print "PLPCR1 ".Dumper(\$plinfo);
    my $filename = $plinfo->{fileName};

    my ($chunk,$xsumopt) = plsGetChunkAt($plinfo,$filepos);
    $xsumopt = "" unless defined $xsumopt;

    my $endpos = $filepos + length($chunk);
    if ($endpos == $plinfo->{fileLength}) {
        DPSTD("LAST CHUNK ($endpos/$filepos) OF $plinfo->{filePath} TO ".getDirName($dir));
        if ($xsumopt eq "") {
            DPSTD("WHY IS THERE NO FINAL XSUM HERE?");
        }
    }
    my $pipelineOperationsCode = "P";
    my $dataReplyCode = "D";
    my $pkt = chr(0x80+$dir).chr($CDM_PKT_TYPE).$pipelineOperationsCode.$dataReplyCode;
    $pkt = plAddTagTo($pkt,$outboundTag);
    $pkt = addLenArgTo($pkt,$filepos);
    $pkt = addLenArgTo($pkt,$chunk);
    $pkt = addLenArgTo($pkt,$xsumopt);
    return $pkt;
}

sub plProcessChunkRequest {
    my ($dir,$bref) = @_;
    my $pkt = plProcessChunkRequestAndCreateReply($dir,$bref);
    if (defined($pkt)) {
        DPPKT("CHUNKREPLY($pkt)");
        writePacket($pkt);
    }
}

sub plsCreateChunkRequestPacket {  # Pick from all 'valid' providers
    my ($plinfo,$filepos) = @_;
    die unless defined $filepos;
    my $filename = $plinfo->{fileName};
    my $providermap = plGetProviderMapForFilename($filename);
    my ($windir,$tot) = (undef,0);
    foreach my $dir (keys %$providermap) {
        my $prec = $providermap->{$dir};
        my ($pfx,$sage,$rage) =
            ($prec->[PREC_PFXL],$prec->[PREC_SAGE],$prec->[PREC_RAGE]);
        my $votes = 1;
        next if $filepos > $pfx;
        if (clacksAge($rage) < 20) {  # Among those we've heard from lately,
            $votes += clacksAge($sage); # Favor the ones we haven't asked as much
        }
        $tot += $votes;
        $windir = $dir if oddsOf($votes,$tot);
    }
    return undef unless defined $windir;
    return plCreateChunkRequestPacket($windir, $filename, $filepos);
}

sub plProcessChunkReplyAndCreateNextRequest {
    my ($dir,$bref) = @_;

    my $blen = scalar(@$bref);
    # [0:3] known to be CDM PD type
    my $lenPos = 4;
    my ($inboundTag,$filepos,$chunk,$xsumopt);
    ($inboundTag,$lenPos) = plGetTagArgFrom($lenPos,$bref);
    ($filepos,$lenPos)    = getLenArgFrom($lenPos,$bref);
    $filepos += 0; # destringify
    ($chunk,$lenPos)      = getLenArgFrom($lenPos,$bref);
    ($xsumopt,$lenPos)    = getLenArgFrom($lenPos,$bref);
    DPDBG("RPYacr($inboundTag,$filepos)");
#    print "QQplOUTBOUNDTAGtoPLINFO ".Dumper(\%plOUTBOUNDTAGtoPLINFO);
    my $plinfo = plGetPlinfoFromInboundTag($inboundTag,$dir);
    if (!defined $plinfo) {
        DPSTD("PD: No plinfo for $inboundTag from $dir, ignoring");
        return undef;
    }
    
    my $filename = $plinfo->{fileName};
    my $prec = plGetProviderRecordForFilenameAndDir($filename,$dir);
    $prec->[PREC_RAGE] = now(); # rage refreshes when we recv a chunk replay

#    print "RPYplinfo1 ".Dumper(\$plinfo);

    if ($xsumopt ne "") {
        DPSTD("$plinfo->{fileName} PREFIX EXTENDED TO $filepos");
        plsInsertInXsumMap($plinfo,$filepos,$xsumopt);
        if (plsCheckXsumStatus($plinfo,$xsumopt)) {
            $plinfo->{prefixLengthAvailable} = $filepos;
#            print "pLAnOW=$filepos\n";
        } else {
            die "NONONOOOOWONFONGOIWRONGO\n";
        }
    } else {
        $xsumopt = "";
    }

    my $nowat = plsWriteChunk($plinfo,$chunk,$filepos);
    return undef unless defined $nowat;
    
    $filepos += length($chunk);
    if ($nowat != $filepos) {
        DPSTD(sprintf("PD: LENGTH MISMATCH nowat=%d, filepos=%d, length(chunk)=%d",
                      $nowat, $filepos, length($chunk)));
        die "FAILONGO";
        return undef;
    }

    if ($filepos == $plinfo->{fileLength} && $xsumopt ne "" && length($chunk) == 0) {
        DPSTD("RECVD LAST OF $inboundTag $plinfo->{fileName}");
        return ("",$plinfo);
    }

    # Make request for next chunk!
#    my $chunkpacket = plCreateChunkRequestPacket($dir,$plinfo->{fileName},$filepos);
    my $chunkpacket = plsCreateChunkRequestPacket($plinfo,$filepos);
    if (!defined $chunkpacket) {
        DPSTD("NO CHUNK? FP $filepos, FL $plinfo->{fileLength}, LC "
              .length($chunk).", LX ".length($xsumopt));
        return undef;
    }
    {
        my $requestHZ = 25; # Limit request rate a little bit
        my $rateLimiterUsec = int(1_000_000/$requestHZ);
        Time::HiRes::usleep($rateLimiterUsec);
    }
    return ($chunkpacket,$plinfo);
}

sub plProcessChunkReply {
    my ($dir,$bref) = @_;
    my ($pkt,$plinfo) = plProcessChunkReplyAndCreateNextRequest($dir,$bref);
    if (defined $pkt) {
        DPPKT("CHUNKRESPONSE($pkt)");
        if ($pkt ne "") {
            writePacket($pkt);
        } else {
            defined $plinfo or die;
            plsCheckAndReleasePipelineFile($plinfo);
        }
    }
}

sub plsCheckAndReleasePipelineFile {
    my $plinfo = shift or die;
    if (defined $plinfo->{finfo}) {
        die "XXX WRITE ME?";
    }
    my $filename = $plinfo->{fileName};
    my $curpath = $plinfo->{filePath};
    my $destpath = "$pendingPath/$plinfo->{fileName}";
    move($curpath,$destpath);
    my $finfo = getFinfoFrom($filename,$pendingSubdir);
    $finfo->{checksum} = $plinfo->{fileChecksum};
    $finfo->{innerTimestamp} = $plinfo->{fileInnerTimestamp};
#    print "CRAPX ".Dumper(\$finfo);
#    print "CRAPY ".Dumper(\$plinfo);
    checkAndReleasePendingFile($finfo);
    $plinfo->{finfo} = $finfo;
    $plinfo->{filePath} = getFinfoPath($finfo);
}
    

sub plCheckAnnouncedFile {
    my ($filename,$contentLength,$checksum,$timestamp,$tag,$dir) = @_;
    die unless defined $dir;

    DPDBG("CHECKING Ignore complete and matched in common");
    return checkIfFileInCommon($filename,$checksum,$timestamp);
}


sub plProcessFileAnnouncement {
    my ($dir,$bref) = @_;
    my $blen = scalar(@$bref);
    # [0:3] known to be CDM PF type
    my $lenPos = 4;
    my ($inboundTag,$filename,$filelength,$fileinnertimestamp,$filechecksum);
    ($inboundTag,$lenPos)         = plGetTagArgFrom($lenPos,$bref);
    ($filename,$lenPos)           = getLenArgFrom($lenPos,$bref);
    ($filelength,$lenPos)         = getLenArgFrom($lenPos,$bref);
    ($fileinnertimestamp,$lenPos) = getLenArgFrom($lenPos,$bref);
    ($filechecksum,$lenPos)       = getLenArgFrom($lenPos,$bref);

    my $plinfo = plFindPLS($filename);
    if (!$plinfo || $plinfo->{fileInnerTimestamp} < $fileinnertimestamp) {
        $plinfo = plSetupNewPipelineFile($filename,$filelength,$filechecksum,$fileinnertimestamp);
        plSetPlinfoAsSourceAndInit($plinfo);
        DPSTD("(RE)INITTED PIPELINE $filename => $inboundTag, SOURCE $dir");
    }
#    print "plProcessFileAnnouncement GOGOGOGOG".Dumper($plinfo);
    plPutOnInboundTag($inboundTag,$dir,$plinfo);
    my $prec = plGetProviderRecordForFilenameAndDir($filename, $dir);
    $prec->[PREC_RAGE] = now(); # Let's say we've heard from them
#    print "PREC ".Dumper($prec);
    plCheckAnnouncedFile($filename,$filelength,$filechecksum,$fileinnertimestamp,$inboundTag,$dir)
}

sub plGetProviderMapForFilename {
    my $filename = shift or die;
    my $providermap = $plFILEtoPROVIDER{$filename};
    if (!defined $providermap) {
        $providermap = {};
        $plFILEtoPROVIDER{$filename} = $providermap;
#        print "F2P111 ".Dumper(\%plFILEtoPROVIDER);
#        DPDBG("GPMFO $filename $providermap");
    }
    return $providermap;
}

sub plGetProviderRecordForFilenameAndDir {
    my ($filename,$dir) = @_;
    my $providermap = plGetProviderMapForFilename($filename);
    my $prec = $providermap->{$dir};
#    DPDBG("GF1XX $filename $dir $providermap");
    if (!defined $prec) {
        $prec =
            [
             $dir,   #[0] dir
             0,      #[1] tag
             0,      #[2] prefixlen
             0,      #[3] sage
             0       #[4] rage
            ];
        $providermap->{$dir} = $prec;
#        DPDBG("GF2XX $filename $dir prc=".join(", ",@$prec));
#        print "F2P222 ".Dumper(\%plFILEtoPROVIDER);
    }
    return $prec; 
}

sub plProcessPacket {
    my $bref = shift;
    my $blen = scalar(@$bref);
    if ($blen < 4) {
        DPSTD("Short PL packet '$pkt' ignored");
        return;
    }
    my $dir = ord($bref->[0])&0x7;
    # [0:2] known to be CDM P type
    my $plCmd = $bref->[3];
    if ($plCmd eq "F") {
        plProcessFileAnnouncement($dir, $bref);
        return;
    }

    if ($plCmd eq "A") {
        plProcessPrefixAvailability($dir, $bref);
        return;
    }

    if ($plCmd eq "R") {
        plProcessChunkRequest($dir, $bref);
        return;
    }

    if ($plCmd eq "D") {
        plProcessChunkReply($dir, $bref);
        return;
    }

    DPSTD("Unrecognized PL operation '$plCmd' ignored");
}

sub ceiling {
    my $n = shift;
    return ($n == int $n) ? $n : int($n + 1);
}

sub max {
    my ($n,$m) = @_;
    return ($n >= $m) ? $n : $m;
}

sub indexOfLowestAtLeast {
    my ($mapref, $value) = @_;
    my $pairlen = scalar(@{$mapref});
    return 1 if $pairlen == 0; # Off end of empty
    die if $pairlen < 2 or $pairlen&1;
    my ($loidx,$hiidx) = (0, $pairlen/2-1);
#    DPSTD("indexOfLowestAtLeast($loidx,$hiidx,$pairlen)WANT($value)");
    while ($loidx < $hiidx) {
        my $mididx = int(($hiidx+$loidx)/2);
        my $midv = $mapref->[2*$mididx];
#    DPSTD("LO $loidx ".$mapref->[2*$loidx]);
#    DPSTD("HI $hiidx ".$mapref->[2*$hiidx]);
#    DPSTD("MD $mididx: $midv <> $value");
        if ($midv == $value) {
            return $mididx;
        } elsif ($midv < $value) {
            $loidx = $mididx+1;
        } else { # ($midv > $value) 
            $hiidx = $mididx;
        } 
    }
    my $lastv = $mapref->[2*$loidx];
#    DPSTD("OUT $loidx $hiidx $lastv $value");
    return ($lastv >= $value) ? $loidx : $loidx + 1;
}

sub plsInsertInXsumMap {
    my ($plinfo, $filepos, $xsum) = @_;
    defined $xsum or die;
    my $aref = $plinfo->{xsumMap};
    defined $aref or die;
    my $overidx = indexOfLowestAtLeast($aref,$filepos);
    if (2*$overidx >= scalar(@{$aref})) {
        push @{$aref}, $filepos, $xsum;
#        DPSTD("INSERTATEND($overidx,$filepos,$xsum)");
    } else {
        my $overkey = $aref->[2*$overidx];
        if ($overkey == $filepos) {
            my $overv = $aref->[2*$overidx+1];
            if ($overv eq $xsum) {
                DPSTD("MATCHED $filepos,$xsum");
            } else {
                DPSTD("REPLACED? $filepos:$overv->$xsum");
                $aref->[2*$overidx+1] = $xsum;
            }
        } else {
            splice @{$aref},2*$overidx,0,$filepos,$xsum;
            DPSTD("INSERTBEFORE($overkey, $filepos, $xsum)");
        }
    }
}


sub plsFindXsumInRange {
    my ($plinfo, $lo, $hi) = @_;
    return undef if $lo > $hi;
    my $aref = $plinfo->{xsumMap};
    my $loidx = indexOfLowestAtLeast($aref, $lo);
    my $hiidx = indexOfLowestAtLeast($aref, $hi+1);
    return ($loidx != $hiidx) ? ($aref->[2*$loidx], $aref->[2*$loidx+1]) : undef;
}

sub plsBuildXsumMap {
    my $plinfo = shift or die;
#    print "plsBuildXsumMap ".Dumper($plinfo);
    $plinfo->{xsumMap} = [];
    my $path = $plinfo->{filePath};
    my $XSUM_PIECE_COUNT = 100;
    my $chunksize = max(1<<12,ceiling($plinfo->{fileLength}/$XSUM_PIECE_COUNT));
     $digester->reset();
    open(HDL,"<",$path) or die "Can't read $path: $!";
    my $position = 0;
    my $lastposition = -1;
    while (1) {
        my $data;
        my $count = read HDL,$data,$chunksize;
        die "Bad read $path: $!" unless defined $count;
        $position += $count;
        $digester->add($data);
        if ($lastposition != $position) {
            plsInsertInXsumMap($plinfo, $position, $digester->clone->b64digest()); # food dog own eat
#            push @{$plinfo->{xsumMap}}, $position, $digester->clone->b64digest();
            $lastposition = $position;
        }
#        DPSTD("$position $count $chunksize =".$plinfo->{xsumMap}->{$position});
        last if $count == 0;
    }
    close HDL or die "Can't close $path: $!";
    return $plinfo;
}

sub testShimForTag {
    for (my $i = 0; $i < 10; ++$i) {
        my $tag = plNewTag();
        my $pkt = chr($i).":";
        $pkt = plAddTagTo($pkt,$tag);
        $pkt .= "!";
        $pkt = plAddTagTo($pkt,$tag+1);
        printf("$i 0x%08x %s\n",$tag,$pkt);
        my @bytes = split(//,$pkt);
        my $bref = \@bytes;
        my $lenpos = 2; # skip i:
        my ($utag1, $utag2);
        ($utag1,$lenpos) = plGetTagArgFrom($lenpos,$bref);
        ($utag2,$lenpos) = plGetTagArgFrom($lenpos+1,$bref); # skip !
        printf("$i 0x%08x 0x%08x 0x%08x \n",$tag,$utag1,$utag2);
    }
}

sub testShimForXsumMap {
    my $plinfoCommon = shift;
    foreach my $v (100000, 113580, 113580+1,0,1892908,1892907,1892908+1) {
        my $mapref = $plinfoCommon->{xsumMap};
        my $idx = indexOfLowestAtLeast($mapref, $v);
        my $kidx = 2*$idx;
        my $vidx = 2*$idx+1;
        my $key = $kidx < scalar @{$mapref} ? $mapref->[$kidx] : -1;
        my $val = $vidx < scalar @{$mapref} ? $mapref->[$vidx] : -1;
        print "IoLAL $v: $idx => $key, $val\n";
    }
    foreach my $v (100000, 113580, 113580+1, 113580-100, 0,1892908,1892907,1892908+1) {
        my $hi = $v+100;
        my ($pos,$xsum) = plsFindXsumInRange($plinfoCommon,$v,$hi);
        if (defined $xsum) {
            print "pFXIR $v..$hi: $pos, $xsum\n";
        } else {
            print "pFXIR $v..$hi: undef\n";
        }
    }
    foreach my $v ([1684770, 'Nx2WLV4IqyuB1w2z9XTKZpRwYSIkQE8X/adX2aZVnAg'],
                   [1836210, 'r4PTseL7htd7LWFMtdO/8p54Ry+evFjsaM6teTt4Eow'],
                   [1836210, 'DIFFseL7htd7LWFMtdO/8p54Ry+evFjsaM6teTt4Eow'],
                   [1400819, 'BEFOREZ7bYnUJx0/TkHrA0yt8syvj/EuS6F1Yrn4yOk'],
                   [0, 'WAY START'],
                   [0, 'WAY START REPLACE'],
                   [1, 'NEAR START'],
                   [1892908, 'AT ENDLCnmI61tHUddndA3dG3cP/aRsOIO7Td1MoAGc'],
                   [1892909, 'PAST END MANO HUddndA3dG3cP/aRsOIO7Td1MoAGc']) {
        my ($filepos,$xsum) = @{$v};
        DPSTD("INSDERT($filepos,$xsum)");
        plsInsertInXsumMap($plinfoCommon,$filepos,$xsum);
        DPSTD("INSDERTED($filepos,$xsum)");
    }
    print "TESTSHIMFINAL".Dumper($plinfoCommon);
}

sub testShimForTagMap {
    plInitTagsAndProviders();
    my (@fixedtags, @vartags);
    for (my $i = 0; $i < 8; ++$i) {
        my $tag = plNewTag();
        push @fixedtags, $tag;
        my $filename0 = "fnFIXED.mfz";
        plPutFilenameOnTag($tag,$i,$filename0);

        $tag = plNewTag();
        push @vartags, $tag;
        my $filename1 = "fn".$i.".mfz";
        plPutFilenameOnTag($tag,$i,$filename1);
    }
    print "SDMFTAGM".Dumper(\%plPROVIDERtoFILE);
}

sub testShimForPlinfoGrow {
    plInitTagsAndProviders();

    my $finfo = shift or die;
    my $ngb = getNgbInDir(1);
    my $origfilename = $finfo->{filename};

    my $plinfoCommon = plSetupCommonFile($finfo);

    my $hackfilename = "HACK".$origfilename;
    my $plinfoPipeline =
        plSetupNewPipelineFile($hackfilename,
                               $plinfoCommon->{fileLength},
                               $plinfoCommon->{fileChecksum},
                               $plinfoCommon->{fileInnerTimestamp});
    my $outboundTag = $plinfoPipeline->{outboundTag};
    plPutOnTag($outboundTag,$ngb->{dir},$plinfoPipeline);
    my $prec = plGetProviderRecordForFilenameAndDir($hackfilename, $ngb->{dir});

    print "PLINFOCOMMON ".Dumper($plinfoCommon);

    my $filepos = 0;
    while (1) {
        my ($chunk,$xsumopt) = plsGetChunkAt($plinfoCommon,$filepos);
        if (!defined $chunk) {
            print "NO MORE CHUNKS\n";
            last;
        }
        if (defined $xsumopt) {
            plsInsertInXsumMap($plinfoPipeline,$filepos,$xsumopt);
            if (plsCheckXsumStatus($plinfoPipeline,$xsumopt)) {
                $plinfoPipeline->{prefixLengthAvailable} = $filepos;
                print "pLA=$filepos\n";

            } else {
                die "WONFONGOIWRONGO\n";
            }
        } else {
            $xsumopt = "";
        }
        my $nowat = plsWriteChunk($plinfoPipeline,$chunk,$filepos);
        #print "FPXS: $filepos $xsumopt\n";
        $filepos += length($chunk);
        if ($nowat != $filepos) {
            DPSTD("$nowat vs $filepos INCONSISTO\n");
        }
        last if ($filepos == $plinfoCommon->{fileLength} && $chunk eq "");
    }
    print "FPXS! Done at $filepos\n";
    print "POSTPLINFOPIPELINE ".Dumper($plinfoPipeline);
}

sub testShimForChunkMovement {
    plInitTagsAndProviders();

    my $finfo = shift or die;
    my $ngb = getNgbInDir(1);

    print "FINFO ".Dumper($finfo);
    my $plinfoCommon = plSetupCommonFile($finfo);
    print "PLINFOCOMMONG ".Dumper($plinfoCommon);

    my $origfilename = $plinfoCommon->{fileName};
    my $hackfilename = "HACK2".$origfilename;

    $plinfoCommon->{fileName} = $hackfilename;
    my $announcePacket = plCreatePipelineFileAnnouncementPacket($ngb,$plinfoCommon);
    $plinfoCommon->{fileName} = $origfilename;

    # 'send' pipeline packet for, should init pipeline for hackfilename
    processPacket($announcePacket);

    my $pls = plFindPLS($origfilename);
    print "PLS1READY ".Dumper($pls);

    my $pls2 = plFindPLS($hackfilename);
    print "PLS2READY ".Dumper($pls2);

    print "plP2FZZ ".Dumper(\%plPROVIDERtoFILE);
    print "plF2PZZ ".Dumper(\%plFILEtoPROVIDER);

    ## Now send an availability notice -- should get handled by pipeline file
    my $availpacket = plCreatePipelinePrefixAvailabilityPacket($ngb,$pls);
    processPacket($availpacket);

    print "HACKPOSTAVAIL ".Dumper($pls2);
    print "XXXKS2A ".Dumper(\%plFILEtoPROVIDER);

    ## now we need a loop to simulate requesting sending and receiving chunks
    my $filepos = 0;
    ## Find a provider who can help us
    my $chunkpacket = plCreateChunkRequestPacket($ngb->{dir},$hackfilename,$filepos);
    if (!defined $chunkpacket) {
        DPDBG("NO CHUNKS");
        last;
    }
    print "CHNKPKT '$chunkpacket' ".join(",",map(ord,split(//,$chunkpacket)))."\n";
    my @bytes;
    for (my $i = 0; $i < 1000; ++$i) {
        ## going to fake around this call: processPacket($chunkpacket);
        @bytes = split(//,$chunkpacket);
        my $reply = plProcessChunkRequestAndCreateReply($ngb->{dir},\@bytes);

        DPPKT("[[[$i]]] GOTREPLY ".length($reply));
        @bytes =  split(//,$reply);
        my ($nextrequest,$plinfo) =
            plProcessChunkReplyAndCreateNextRequest($ngb->{dir},\@bytes);
        die unless defined $nextrequest;
        if (length($nextrequest) == 0) {
            DPSTD("RELEASE HERENOW???");
            plsCheckAndReleasePipelineFile($plinfo);
            DPSTD("RELEASE HERENOW NOYES???");
            last;
        }
        $chunkpacket = $nextrequest;
    }
}

sub newmain {
    STDOUT->autoflush(1);
    flushPendingDir();
    plFlushPipelineDir();
    checkInitDirs();
    loadCommonMFZFiles();

    ### INIT A SINGLE common/ file
    die "Need a .mfz in $commonPath" if scalar(@pathsToLoad) == 0;
    my $filename = shift @pathsToLoad;
    my $finfo = getFinfoFromCommon($filename);
    my $path = getFinfoPath($finfo) || die "No path";
    checkMFZDataFor($finfo);
    my $seqno = assignSeqnoAndCaptureModtime($finfo,$path);
    $finfo->{checksum} = checksumWholeFile($path);

#    testShimForXsumMap($plinfoCommon);
#    testShimForXsumMap(plSetupNewPipelineFile("foo","1234567","checksumbaby",88888888));
#    testShimForTag();
#    testShimForTagMap();
#    testShimForPlinfoGrow($finfo);
    testShimForChunkMovement($finfo);
    print "XXplFILEtoPLINFO ".Dumper(\%plFILEtoPLINFO);
    print "XXplOUTBOUNDTAGtoPLINFO ".Dumper(\%plOUTBOUNDTAGtoPLINFO);
    print "XXplFILEtoPROVIDER ".Dumper(\%plFILEtoPROVIDER);
    print "plP2FZZ ".Dumper(\%plPROVIDERtoFILE);
    print "plF2PZZ ".Dumper(\%plFILEtoPROVIDER);
    print "GOODBYE\n";
    exit 3;
}

sub main {
    STDOUT->autoflush(1);

    flushPendingDir();
    plFlushPipelineDir();

    checkInitDirs();
    preinitCommon();

    plInitTagsAndProviders();
    # plPreinitCommonFiles();  

    openPackets();
    flushPackets();
    eventLoop();
    closePackets();
}


main();


