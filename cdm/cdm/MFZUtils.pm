## Module stuff
package MFZUtils;
use strict;

use Exporter qw(import);

## Imports
use Carp;
use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempdir);
use IO::Compress::Zip qw($ZipError);
use IO::Uncompress::Unzip qw($UnzipError);
use MIME::Base64 qw(encode_base64 decode_base64);
use Digest::SHA qw(sha512_hex sha512);
use Crypt::OpenSSL::RSA;

## Constants
use constant MFZ_VERSION => "1.0";
use constant MFZRUN_HEADER => "MFZ(".MFZ_VERSION.")\n";
use constant MFZ_PUBKEY_NAME => "MFZPUBKEY.DAT";
use constant MFZ_FILE_NAME => "MFZNAME.DAT";
use constant MFZ_SIG_NAME => "MFZSIG.DAT";
use constant MFZ_ZIP_NAME =>  "MFZ.ZIP";
use constant CDM_FORMAT_MAGIC => "CDM";
use constant CDM_FORMAT_VERSION_MAJOR => "1";
use constant CDM_FORMAT_VERSION_MINOR => "0";

use constant CDM10_PACK_SIGNED_DATA_FORMAT =>
    ""            #   0
    ."a6"         #   0 +   6 =    6 magic + maj + min + \n
    ."C1"         #   6 +   1 =    7 bits in block size
    ."C1"         #   7 +   1 =    8 regnum
    ."N"          #   8 +   4 =   12 slotstamp
    ."N"          #  12 +   4 =   16 mapped file length
    ."a16"        #  16 +  16 =   32 label
    ."a64"        #  32 +  64 =   96 sha512 mapped file checksum
    ."(a8)100"    #  96 + 800 =  896 100*8 byte xsum map
    #  896 total length
    ;

use constant CDM10_PACK_FULL_FILE_FORMAT =>
    ""            #   0
    ."a896"       #   0 + 896 =  896 as from CDM10_PACK_SIGNED_DATA_FORMAT
    ."a128"       # 896 + 128 = 1024 RSA sig by regnum of bytes 0..895
    # 1024 total length
    ;

use constant CDM10_FULL_MAP_LENGTH => 1024;

## DeletedMap
use constant DELETED_SLOT_NUMBER => 0x01;

#DMP10\n
use constant DELETED_MAP_SIGNED_DATA_FORMAT =>
    ""            #   0
    ."a6"         #   0 +   6 =    6 magic + maj + min + \n
    ."C1"         #   6 +   1 =    7 regnum
    ."N"          #   7 +   4 =   11 signing slot stamp
    ."a37"        #  11 +  37 =   48 reserved
    ."N256"       #  40 +1024 = 1072 256*4 flagstamp map
    #  1072 total length
    ;

use constant DELETED_MAP_FULL_FILE_FORMAT =>
    ""            #   0
    ."a1072"      #   0 +1072 = 1072 as from DELETED_MAP_SIGNED_DATA_FORMAT
    ."a*"         #1072 + 128 = 1200 RSA sig by regnum of bytes 0..895
    # 1200 total length
    ;

use constant DELETED_MAP_DATA_LENGTH => 1072;
use constant DELETED_MAP_FULL_FILE_LENGTH => 1200;

use constant DELETED_FLAG_SLOT_VALID =>   (1<<0);
use constant DELETED_FLAG_SLOT_DELETED => (1<<1);
use constant DELETED_FLAG_SLOT_RSRV2 =>   (1<<2);
use constant DELETED_FLAG_SLOT_RSRV3 =>   (1<<3);
use constant DELETED_FLAG_SLOT_RSRV4 =>   (1<<4);
use constant DELETED_FLAG_SLOT_RSRV5 =>   (1<<5);
use constant DELETED_FLAG_SLOT_RSRV6 =>   (1<<6);
use constant DELETED_FLAG_SLOT_RSRV7 =>   (1<<7);

##cdmctl
use constant DELETEDS_MAP_NAME => "cdmss-deleted.map";

use constant SS_SLOT_BITS => 8;
use constant SS_SLOT_MASK => (1<<SS_SLOT_BITS)-1;
use constant SS_STAMP_BITS => 24;
use constant SS_STAMP_MASK => (1<<SS_STAMP_BITS)-1;

use constant SS_SECS_PER_STAMP => 60*5; # Five minute slotstamp time granularity

my @zipOtherOptions;
ConfigureZipOptions();  # Ubuntu 12.04's zip module doesn't know CanonicalName! :(

my @constants = qw(
    MFZ_VERSION
    MFZRUN_HEADER
    MFZ_FILE_NAME
    MFZ_SIG_NAME
    MFZ_ZIP_NAME

    CDM_FORMAT_MAGIC
    CDM_FORMAT_VERSION_MAJOR
    CDM_FORMAT_VERSION_MINOR

    CDM10_PACK_SIGNED_DATA_FORMAT
    CDM10_PACK_FULL_FILE_FORMAT
    CDM10_FULL_MAP_LENGTH

    DELETEDS_MAP_NAME

    DELETED_SLOT_NUMBER
    DELETED_MAP_SIGNED_DATA_FORMAT
    DELETED_MAP_FULL_FILE_FORMAT
    DELETED_MAP_DATA_LENGTH
    DELETED_MAP_FULL_FILE_LENGTH
    DELETED_FLAG_SLOT_VALID
    DELETED_FLAG_SLOT_DELETED
    DELETED_FLAG_SLOT_RSRV2
    DELETED_FLAG_SLOT_RSRV3
    DELETED_FLAG_SLOT_RSRV4
    DELETED_FLAG_SLOT_RSRV5
    DELETED_FLAG_SLOT_RSRV6
    DELETED_FLAG_SLOT_RSRV7

    SS_SLOT_BITS
    SS_SLOT_MASK
    SS_STAMP_BITS
    SS_STAMP_MASK
    SS_SECS_PER_STAMP

    );

my @functions = qw(
    CDMakeMFZ
    CheckForPubKey
    ComputeChecksumOfString
    ComputeChecksumPrefixOfString
    ComputeFingerprintFromFullPublicKey
    EscapeHandle
    FindName
    GetConfigDir
    GetDefaultHandle
    GetDefaultHandleFile
    GetHandleIfLegalRegnum
    GetKeyDir
    GetLegalHandle
    GetLegalRegnum
    GetPrivateKeyDir
    GetPrivateKeyFile
    GetPublicKeyDir
    GetPublicKeyFile
    GetValidRegnums
    IDie
    InitMFMSubDir
    JoinHandleToKey
    KDGetVerb
    LastArg
    LoadInnerMFZToMemory
    LoadOuterMFZToMemory
    MakeCDMMap
    NextArg
    NoVerb
    ReadPrivateKeyFile
    ReadPublicKeyFile
    ReadWholeFile
    ReadableFileOrDie
    RestOfArgs
    SSDominatesSS
    SSFromPath
    SSMake
    SSSlot
    SSStamp
    SSStampFromTime
    SSToFileName
    SSToTag
    SScmpSS
    SetError
    SetKeyDir
    SetProgramName
    SetUDieMsg
    SignString
    SignStringRaw
    SplitHandleFromKey
    UDie
    UntaintHandleIfLegal
    UnzipStream
    UnzipStreamToMemory
    VersionExit
    WritableFileOrDie
    WriteWholeFile
    ZipTimeNow
    );

our @EXPORT_OK = (@constants, @functions);
our %EXPORT_TAGS =
    (
     constants => \@constants,
     functions => \@functions,
     all => \@EXPORT_OK
    );


my $programName = $0;  # default
sub SetProgramName {
    $programName = shift;
}


sub IDie {
    my $msg = shift;
    print STDERR "\nInternal Error: $msg\n";
    confess "I suck";
}

my $UDIE_MSG;
sub SetUDieMsg {
    $UDIE_MSG = shift;
}

sub UDie {
    my $msg = shift;
    IDie("Unset UDie message") unless defined $UDIE_MSG;
    print STDERR "\nError: $msg\n";
    print STDERR $UDIE_MSG;
    exit(1);
}

sub NoVerb {
    UDie("Missing command");
}

my $KeyDir;

sub InitMFMSubDir {
    my $sub = shift;
    IDie "No sub?" unless defined $sub;
    IDie "No KD?" unless defined $KeyDir;

    my $dir = "$KeyDir/$sub"; # $KeyDir should be clean and $sub should be internal

    if (!-d $dir) {
        make_path($dir)       # So we shouldn't need untainting to do this
            or die "Couldn't mkdir $dir: $!";
    }
    return $dir;
}

sub GetPublicKeyDir {
    return InitMFMSubDir("public_keys");
}

sub GetPublicKeyFile {
    my $handle = shift;
    my $ehandle = EscapeHandle($handle);
    my $dir = GetPublicKeyDir();
    my $pub = "$dir/$ehandle.pub";

    return $pub;
}

sub JoinHandleToKey {
    my ($handle, $keydata) = @_;
    my $data ="[MFM-Handle:$handle]\n$keydata";
    return $data;
}

sub SplitHandleFromKey {
    my $data = shift;
    $data =~ s/^\[MFM-Handle:(:?[a-zA-Z][-., a-zA-Z0-9]{0,62})\]\r?\n//
        or return undef;
    my $handle = $1;
    return ($handle,$data);
}

sub ComputeFingerprintFromFullPublicKey {
    my $fullpubkey = shift;
    my $fingerprint = lc(sha512_hex($fullpubkey));
    $fingerprint =~ s/^(....)(...)(....).+$/$1-$2-$3/
        or IDie("you're a cow");
    return $fingerprint;
}

sub ComputeChecksumOfString {
    my $string = shift;
    my $fingerprint = lc(sha512_hex($string));
    $fingerprint =~ s/^(......)(..).+(..)(......)$/$1-$2$3-$4/
        or IDie("give me some milk or else go home");
    return $fingerprint;
}

sub ComputeChecksumPrefixOfString {
    my ($string,$len) = @_;
    IDie("something is happening here but you don't know what it is")
        unless defined $len && $len >= 0 && $len <= 64;
    my $checksum = sha512($string);
    return substr($checksum,0,$len);
}

sub ReadPublicKeyFile {
    my $handle = shift;
    my $file = GetPublicKeyFile($handle);
    my $data = ReadWholeFile($file);
    my ($pubhandle, $key) = SplitHandleFromKey($data);
    UDie("Bad format in public key file '$file' for '$handle'")
        unless defined $pubhandle;
    UDie("Non-matching handle in public key file '$file' ('$handle' vs '$pubhandle')")
        unless $pubhandle eq $handle;
    return ($key, ComputeFingerprintFromFullPublicKey($data));
}

sub GetConfigDir {
    my $cfgdir = InitMFMSubDir("config");
    chmod 0700, $cfgdir;
    return $cfgdir;
}

sub GetLegalHandle {
    my $handle = shift;
    if ($handle eq "-") {
        my $defaulthandle = GetDefaultHandle();
        if (!defined $defaulthandle) {
            print STDERR "ERROR: No default handle, so cannot use '-' as handle (try 'mfzmake help'?)\n";
            exit 1;
        }
        return $defaulthandle;
    }

    UntaintHandleIfLegal(\$handle)
        or UDie("Bad handle '$handle'");
    return $handle;
}

my %unrevokedRegnumHandles = (
    0 => "gold-keymaster-release-10"
    );

# Return list of valid/unrevoked regnums
sub GetValidRegnums {
    return sort keys %unrevokedRegnumHandles;
}

sub GetHandleIfLegalRegnum {
    my $regnum = shift;
    return SetError("Not a number '$regnum'") unless $regnum =~ /^(\d+)$/;
    my $num = $1;
    return SetError("Illegal regnum $num")    unless $regnum >= 0 && $regnum < (1<<16);
    my $handle = $unrevokedRegnumHandles{$num};
    return SetError("Invalid regnum $num")    unless defined $handle;
    return $handle;
}

sub GetLegalRegnum {
    my $regnum = shift;
    UDie("Not a number '$regnum'")
        unless $regnum =~ /^(\d+)$/;
    my $num = $1;
    UDie("Illegal regnum $num")
        unless $regnum >= 0 && $regnum < (1<<16);
    my $handle = $unrevokedRegnumHandles{$num};
    UDie("Invalid regnum $num")
        unless defined $handle;
    return ($num, $handle);
}

sub GetDefaultHandleFile {
    my $dir = GetConfigDir();
    my $def = "$dir/defaultHandle";
    return $def;
}

sub GetDefaultHandle {
    my $file = GetDefaultHandleFile();
    if (-r $file) {
        my $handle = ReadWholeFile($file);
        return $handle if UntaintHandleIfLegal(\$handle);
    }
    return undef;
}

sub GetPrivateKeyDir {
    my $privdir = InitMFMSubDir("private_keys");
    chmod 0700, $privdir;
    return $privdir;
}

sub GetPrivateKeyFile {
    my $handle = shift;
    my $ehandle = EscapeHandle($handle);
    my $dir = GetPrivateKeyDir();
    my $pub = "$dir/$ehandle.priv";
    return $pub;
}

sub ReadPrivateKeyFile {
    my $handle = shift;
    my $file = GetPrivateKeyFile($handle);
    my $data = ReadWholeFile($file);
    my ($privhandle, $key) = SplitHandleFromKey($data);
    UDie("Bad format in private key file for '$handle'")
        unless defined $privhandle;
    UDie("Non-matching handle in private key file ('$handle' vs '$privhandle')")
        unless $privhandle eq $handle;
    return $key;
}

sub VersionExit {
    my $pname = shift;
    $pname = "" unless defined $pname;
    print "$pname-".VERSION."\n";
    exit(0);
}

sub GetKeyDir {
    IDie("No key dir?") unless defined $KeyDir;
    return $KeyDir;
}

sub KDGetVerb {
    my $mustExist = shift;
    my $verb = NextArg();
    NoVerb() if $mustExist && !defined $verb;
    my $kdir;
    if (defined($verb) && $verb eq "-kd") {
        $kdir = NextArg();
        UDie("Missing argument to '-kd' switch")
            unless defined $kdir;
        $verb = NextArg();
        NoVerb() if $mustExist && !defined $verb;
    }

    SetKeyDir($kdir);

    return $verb;
}

sub SetKeyDir {
    my $kdir = shift;
    $kdir = glob "~/.mfm" unless defined $kdir;

    # Let's avoid accidentally creating keydir 'help' or whatever..
    UDie("-kd argument ('$kdir') must begin with '/', './', or '../'")
        unless $kdir =~ m!^([.]{0,2}/.*)$!;
    $KeyDir = $1;

    if (-e $KeyDir) {
        UDie("'$KeyDir' exists but is not a directory")
            if ! -d $KeyDir;
    }
}

sub NextArg {
    my $arg = shift @ARGV;
    return $arg;
}

sub LastArg {
    my $arg = NextArg();
    my @more = RestOfArgs();
    UDie("Too many arguments: ".join(" ",@more))
        if scalar(@more);
    return $arg;
}

sub RestOfArgs {
    my @args = @ARGV;
    @ARGV = ();
    return @args;
}

sub ReadableFileOrDie {
    my ($text, $path) = @_;
    UDie "No $text provided" unless defined $path;
    UDie "Non-existent or unreadable $text: '$path'"
        unless -r $path and -f $path;
    $path =~ /^(.+)$/
      or IDie("am i here all alone");
    return $1;
}

sub WritableFileOrDie {
    my ($text, $path) = @_;
    UDie "No $text provided" unless defined $path;
    UDie "Unwritable $text: '$path': $!" unless -w $path or !-e $path;
    $path =~ /^(.+)$/
      or IDie("hands you a bone");
    return $1;
}

sub ReadWholeFile {
    my $file = shift;
    open (my $fh, "<", $file) or IDie("Can't read '$file': $!");
    local $/ = undef;
    my $content = <$fh>;
    close $fh or IDie("Failed closing '$file': $!");
    return $content;
}

sub WriteWholeFile {
    my ($file, $content, $perm) = @_;
    open (my $fh, ">", $file) or UDie("Can't write '$file': $!");
    chmod $perm, $fh
        if defined $perm;
    print $fh $content;
    close $fh or IDie("Failed closing '$file': $!");
}

sub UntaintHandleIfLegal {
    my $ref = shift;
    return 0
        unless $$ref =~ /^\s*(:?[a-zA-Z][-., a-zA-Z0-9]{0,62})\s*$/;
    $$ref = $1;
    return 1;
}

sub EscapeHandle {
    my $handle = shift;
    chomp($handle);
    $handle =~ s/([^a-zA-Z0-9])/sprintf("%%%02x",ord($1))/ge;
    return $handle;
}

sub UnzipStreamToMemory {
    my ($u) = @_;
    my @paths;

    my $status;
    my $count = 0;
    for ($status = 1; $status > 0; $status = $u->nextStream(), ++$count) {
        my $header = $u->getHeaderInfo();
        my $stored_time = $header->{'Time'};
        $stored_time =~ /^(\d+)$/ or die "Bad stored time: '$stored_time'";
        $stored_time = $1;  # Untainted

        my $fullpath = $header->{Name};
        my (undef, $path, $name) = File::Spec->splitpath($fullpath);

        if ($name eq "" or $name =~ m!/$!) {
            last if $status < 0;
        } else {

            my $data = "";
            my $buff;
            while (($status = $u->read($buff)) > 0) {
                $data .= $buff;
            }
            if ($status == 0) {
                push @paths, [$path, $name, $stored_time, $data];
            }
        }
    }

    die "Error in processing: $!\n"
        if $status < 0 ;
    return @paths;
}

sub UnzipStream {
    my ($u, $dest) = @_;
    my @paths;

    $dest = "." unless defined $dest;

    my $status;
    my $count = 0;
    for ($status = 1; $status > 0; $status = $u->nextStream(), ++$count) {
        my $header = $u->getHeaderInfo();
        my $stored_time = $header->{'Time'};
        $stored_time =~ /^(\d+)$/ or die "Bad stored time: '$stored_time'";
        $stored_time = $1;  # Untainted

        my (undef, $path, $name) = File::Spec->splitpath($header->{Name});
        my $destdir = "$dest/$path";

        my $totouch;
        unless (-d $destdir) {
            make_path($destdir)
                or die "Couldn't mkdir $destdir: $!";
            $totouch = $destdir;
        }
        if ($name eq "" or $name =~ m!/$!) {
            last if $status < 0;
        } else {

            my $destfile = "$destdir$name";
            my $buff;
#            print STDERR "Writing $destfile\n";
            my $fh = IO::File->new($destfile, "w")
                or die "Couldn't write to $destfile: $!";
            my $length = 0;
            while (($status = $u->read($buff)) > 0) {
                 $length += length($buff);
#                print STDERR "Read ".length($buff)."\n";
                $fh->write($buff);
            }
            $fh->close();
            $totouch = $destfile;
            push @paths, [$destdir, $name, $stored_time, $length];
        }

        utime ($stored_time, $stored_time, $totouch)
            or die "Couldn't touch $totouch: $!";
    }

    die "Error in processing: $!\n"
        if $status < 0 ;
    return @paths;
}

# Returns:
# undef if $findName (in option $findPath) is not found,
# [$destdir, $name, $stored_time] if $pref is data from UnzipStream
# [$path, $name, $stored_time, $data] if $pref is data from UnzipStreamToMemory

sub FindName {
    my ($pref, $findName, $findPath) = @_;
    my @precs = @{$pref};
    for my $rec (@precs) {
        my @fields = @{$rec};
        my ($path, $name) = @fields;
        if ($name eq $findName) {
            if (!defined($findPath) || $path eq $findPath) {
                return @fields;
            }
        }
    }
    return undef;
}

sub SignStringRaw {
    my ($privkeyfile, $datatosign) = @_;

    my $keystring = ReadWholeFile( $privkeyfile );
    my $privatekey = Crypt::OpenSSL::RSA->new_private_key($keystring);
    $privatekey->use_pkcs1_padding();
    $privatekey->use_sha512_hash();
    my $signature = $privatekey->sign($datatosign);
    return $signature;
}

sub SignString {
    my ($privkeyfile, $datatosign) = @_;
    my $signature = SignStringRaw($privkeyfile, $datatosign);
    return encode_base64($signature, '');
}

sub CheckForPubKey {
    my $handle = shift;
    my $path = GetPublicKeyFile($handle);
    if (-r $path) {
        return ($path, ReadPublicKeyFile($handle));
    }
    return ($path);
}

# First arg is message.  Second arg if any is value to return
sub SetError {
    $@ = shift;
    shift
}

# Returns [$mfzpath, $cdmhdr, \@outerpaths] on success, or undef and sets $@ on error
# DOES NOT DO CRYPTO CHECKS!
sub LoadOuterMFZToMemory {
    my $mfzpath = shift or die;
    return SetError("Can't read '$mfzpath': $!")
        unless open MFZ,"<",$mfzpath;
    my $firstline = <MFZ>;

    my $cdmhdr = "";  # assume none

    if (defined($firstline) && $firstline =~ /^CDM1\d\n$/) { # detect cdmake version 1 header
        $cdmhdr = $firstline;
        my $remainingLen = 1024-6;
        my $data;
        my $read = read MFZ,$data,$remainingLen;
        die "Malformed CDM header or content"
            unless $read == $remainingLen;
        $cdmhdr .= $data;
        $firstline = <MFZ>; # The poifect crime
    }

    return SetError("Bad .mfz header in $mfzpath")
        unless defined $firstline and $firstline eq MFZRUN_HEADER;

    my $u = new IO::Uncompress::Unzip(*MFZ);
    return SetError("Can't unpack '$mfzpath': $UnzipError")
        unless defined $u;

    my @outerpaths = UnzipStreamToMemory($u);

    return SetError("Can't close '$mfzpath': $!")
        unless close MFZ;

    return [$mfzpath, $cdmhdr, \@outerpaths];
}

# Takes [$mfzpath, $cdmhdr, \@outerpaths] as from LoadOuterMFZToMemory
# Returns [$mfzpath, $cdmhdr, \@outerpaths, \@innerpaths, $pubhandle] on verification success, or undef and sets $@ on error
sub LoadInnerMFZToMemory {
    my $oorec = shift or die;
    my $mfzpath = $oorec->[0];
    my $cdmhdr = $oorec->[1];
    my @outerpaths = @{$oorec->[2]};

    my ($sigpath,$signame,undef,$sigdata) = FindName(\@outerpaths,MFZ_SIG_NAME,undef);
    return SetError(".mfz signature not found in $mfzpath")
        unless defined($signame);

    my ($zippath,$zipname,undef,$zipdata) = FindName(\@outerpaths,MFZ_ZIP_NAME,undef);
    return SetError("Can't find ${\MFZ_ZIP_NAME} in $mfzpath")
        unless defined($zipname);

    my $u = new IO::Uncompress::Unzip(\$zipdata);
    return "Cannot read $zippath/$zipname: $UnzipError"
        unless defined($u);

    my @innerpaths = UnzipStreamToMemory($u);

    my ($pubkeypath, $pubkeyname, $pubkeytime, $pubkeydata) = FindName(\@innerpaths,MFZ_PUBKEY_NAME,undef);
    return SetError("Incorrect .mfz packing - missing pubkey")
        unless defined($pubkeyname);

    my $fullpubstring = $pubkeydata;
    my ($pubhandle, $pubkey) = SplitHandleFromKey($fullpubstring);
    return SetError("Bad format public key")
        unless defined($pubhandle);

    my $rsapub = Crypt::OpenSSL::RSA->new_public_key($pubkey);
    $rsapub->use_pkcs1_padding();
    $rsapub->use_sha512_hash();

    my $sig = decode_base64($sigdata);
    return "Invalid signature '$sigdata'/'$sig'"
        unless $rsapub->verify($zipdata, $sig);

    return $@ unless ValidPubKey($pubhandle,$pubkey);

    return [$mfzpath, $cdmhdr, \@outerpaths, \@innerpaths, $pubhandle];
}

sub ValidPubKey {
    my ($handle, $pubstring) = @_;
    my ($path, $knownpub) = CheckForPubKey($handle);
    return SetError("'$handle' not found locally")
        unless defined($knownpub);

    chomp($knownpub);  # Try to normalize last line
    $knownpub .= "\n"; # ending to what we think we expect
    return SetError("'$handle' found locally in '$path', but supplied public key doesn't match!($knownpub:$pubstring)")
        unless $pubstring eq $knownpub;
    return 1;
}

sub ZipTimeNow {
    return int(time()/2)*2; # Default even seconds for ZIP compatibility 
}

sub SSStampFromTime {
    my $sec = shift || ZipTimeNow();
    return (int($sec/SS_SECS_PER_STAMP), $sec);
}

sub SSMake {
    my ($slot,$stamp) = @_;
    die unless defined($slot);
    $stamp = SSStampFromTime() unless defined $stamp;
    my $ss = 0;
    SSSlot(\$ss,$slot);
    SSStamp(\$ss,$stamp);
    return $ss
}

sub SSToTag {
    my $ss = shift || die;
    my $tag = sprintf("%02x-%06x",SSSlot($ss),SSStamp($ss));
    return $tag;
}

sub SSToFileName {
    my $ss = shift || die;
    my $name = "cdmss-".SSToTag($ss).".mfz";
    return $name;
}

# returns 1 if ls dominates rs, 0 if rs dominates ls, undef if neither dominates the other
sub SSDominatesSS {
    my $ls = shift || die;
    my $rs = shift || die;
    my $lslot = SSSlot($ls);
    my $rslot = SSSlot($rs);
    return undef unless $lslot == $rslot;
    my $lstmp = SSStamp($ls);
    my $rstmp = SSStamp($rs);
    return 1 if $lstmp > $rstmp;
    return 0 if $lstmp < $rstmp;
    return undef;
}

# returns 1 if ls dominates rs or has lower sn, -1 if rs dominates ls
# or has lower sn, or 0 if identical
sub SScmpSS {
    my $ls = shift || die;
    my $rs = shift || die;
    my $dom = SSDominatesSS($ls,$rs);
    if (defined($dom)) {
        return $dom ? 1 : -1;
    }
    return  1 if SSSlot($ls) < SSSlot($rs);
    return -1 if SSSlot($ls) > SSSlot($rs);
    return 0;
}

sub SSFromPath {
    my $path = shift || die;
    return undef unless $path =~ m!^(.*?/)?cdmss-([[:xdigit:]]{2})-([[:xdigit:]]{6})[.]mfz$!;
    return SSMake(hex($2),hex($3));
}

sub SSSlot {
    my $sref = shift;
    my $sval = $sref;
    $sval = $$sval if ref($sval) eq 'SCALAR';
    if (defined $_[0]) {
        die "Need scalar ref" unless ref($sref) eq 'SCALAR';
        my $new = shift;
        die unless $new > 0 && $new <= SS_SLOT_MASK;
        $$sref = ($new<<SS_STAMP_BITS)|($$sref&SS_STAMP_MASK);
        $sval = $$sref;
    }
    return ($sval >> SS_STAMP_BITS) & SS_SLOT_MASK;
}

sub SSStamp {
    my $sref = shift;
    my $sval = $sref;
    $sval = $$sval if ref($sval) eq 'SCALAR';
    if (defined $_[0]) {
        die "Need scalar ref" unless ref($sref) eq 'SCALAR';
        my $new = shift;
        die unless $new >= 0 && $new <= SS_STAMP_MASK;
        $$sref = (($$sref&~SS_STAMP_MASK)|$new);
        $sval = $$sref;
    }
    return $sval & SS_STAMP_MASK;
}

############################
# Internal routines
# convert module-name to path

sub GetModuleVersion {
    my $mod = shift;
    my $file = $mod;
    $file =~ s{::}{/}gsmx;
    $file .= '.pm';

    # Pull in the module, if it exists
    eval { require $file }
    or die "can't find module $mod\n";

    # Get the version from the module, if defined
    my $ver;
    { no strict 'refs';
      $ver = ${$mod . "::VERSION"} || 'UNKNOWN';
    }
    return $ver;
}

sub ConfigureZipOptions {
    my $zipVer = GetModuleVersion("IO::Compress::Zip");
    if ($zipVer >= 2.039) {
        @zipOtherOptions = ( CanonicalName => 1 );
    }
#    print "$zipVer/@zipOtherOptions\n";
}

# each @file is either a string file path, or an array ref to [$filename, $data]
sub MakeInnerZip {
    my ($pubkeydata,$mfzfilename,$assignedinnertime,@files) = @_;
    my $compressedoutput;

    my $z = new IO::Compress::Zip
        \$compressedoutput,
        Name          => MFZ_PUBKEY_NAME,
        Time          => $assignedinnertime,
        @zipOtherOptions,
        BinModeIn     => 1
        or IDie("Zip init failed for inner: $ZipError");
    $z->print ($pubkeydata);

    $z->newStream(
        Name          => MFZ_FILE_NAME,
        Time          => $assignedinnertime,
        @zipOtherOptions,
        BinModeIn     => 1)
        or die "Zip reinit failed on ".MFZ_FILE_NAME.": $ZipError\n";
    $z->print ($mfzfilename);

    for my $file (@files) {
        my ($filename,$modtime,$filedata);
        if (ref($file) eq 'ARRAY') {
            die unless @$file == 2;
            $filename = $file->[0];
            $filedata = $file->[1];
            $modtime = $assignedinnertime;
        } else {
            my $origFile = $file;
            $file = abs_path($file);
            # Check top-level special files after path normalization
            UDie("'$origFile' is handled automatically, cannot pack it explicitly")
                if $file eq "/".MFZ_PUBKEY_NAME
                or $file eq "/".MFZ_FILE_NAME;
            $filename = $file;

            open (my $fh, "<", $file) or UDie("Can't read '$file': $!");
            $modtime = (stat($fh))[9];
            while (<$fh>) { $filedata .= $_; }
            close $fh or IDie("Failed closing '$file': $!");
        }
        $z->newStream(
            Name          => $filename,
            @zipOtherOptions,
            BinModeIn     => 1,
            Time          => $modtime,
            ExtAttr       => 0666 << 16)
            or die "Zip reinit failed on '$file': $ZipError\n";
        $z->print ($filedata);
    }

    close $z;
    return $compressedoutput;
}

sub MakeOuterZip {
    my ($signature,$inner,$announce) = @_;
    my $compressedoutput;
    my $z = new IO::Compress::Zip
        \$compressedoutput,
        Name          => MFZ_SIG_NAME,
        @zipOtherOptions,
        BinModeIn     => 1
        or IDie("Zip init failed for outer: $ZipError");
    $z->print($signature);

    $z->newStream(
        Name          => MFZ_ZIP_NAME,
        @zipOtherOptions,
        BinModeIn     => 1,
        ExtAttr       => 0666 << 16)
        or die "Zip reinit failed for outer: $ZipError\n";
    $z->print($inner);

    if (defined $announce) {
        IDie("Why are you here? ANNOUNCING doesn't exist anymore");
    }

    close $z;
    return $compressedoutput;
}

sub MakeCDMMap {
    my ($regnum,$slotnum,$stamptime,$mfzfilename,$privkeyfile,$outer,$innertime,$label) =
        @_;
    my $slotstamp = SSMake($slotnum,$stamptime);
    my $mappedFileLen = length($outer);
    my $bitsInBlock = 8;
    do ++$bitsInBlock while (1<<$bitsInBlock) * 100 < $mappedFileLen;
    my $blockSize = (1<<$bitsInBlock);
    my @xsums = ("") x 100;
    my $sha = Digest::SHA->new(512);
    my $lastfullxsum;
    for (my $block = 0; $block<100;++$block) {
        my $offset = $blockSize*$block;
        last if $offset > $mappedFileLen;
        my $chunk = substr($outer,$offset,$blockSize); # blockSize or til eof
        $sha->add($chunk);
        $lastfullxsum = $sha->clone()->digest();
        my $xsum8 = substr($lastfullxsum,0,8);
        $xsums[$block] = $xsum8;
    }
    my $maptosign =
        pack(CDM10_PACK_SIGNED_DATA_FORMAT,
             CDM_FORMAT_MAGIC.CDM_FORMAT_VERSION_MAJOR.CDM_FORMAT_VERSION_MINOR."\n",
             $bitsInBlock,
             $regnum,
             $slotstamp,
             $mappedFileLen,
             $label,
             $lastfullxsum,
             @xsums);
    IDie("Bad pack") unless length($maptosign) == 896;
    my $signature = SignStringRaw($privkeyfile, $maptosign);
    IDie("Bad sign") unless length($signature) == 128;
    my $cdmmap =
        pack(CDM10_PACK_FULL_FILE_FORMAT,
             $maptosign,
             $signature);
    IDie("Bad map") unless length($cdmmap) == 1024;
    return $cdmmap;
}

# each @file is either a string file path, or an array ref to [$filename, $data]
sub CDMakeMFZ {
    my ($slotnum, $regnum, $label, $innertime, $destdir, @files) = @_;
    my $handle = GetHandleIfLegalRegnum($regnum);
    my ($stamptime) = SSStampFromTime($innertime);
    my $mfzfile = sprintf("cdmss-%02x-%06x.mfz",$slotnum,$stamptime);
    my $mfzpath = "$destdir/$mfzfile";
    UDie("File '$mfzpath' already exists.  Maybe wait a couple minutes, tiger?")
        if -e $mfzpath;
    
    my $privkeyfile = GetPrivateKeyFile($handle);
    $privkeyfile = ReadableFileOrDie("private key file", $privkeyfile);

    my $pubkeyfile =  GetPublicKeyFile($handle);
    $pubkeyfile = ReadableFileOrDie("public key file", $pubkeyfile);

    my $pubkeydata = ReadWholeFile($pubkeyfile);

    $mfzpath = WritableFileOrDie("MFZ path", $mfzpath);
    $mfzpath =~ /[.]mfz$/ or UDie("MFZ filename '$mfzpath' doesn't end in '.mfz'");
    ((!-e $mfzpath) || (-f $mfzpath && -w $mfzpath)) or UDie("MFZ filename '$mfzpath' is not writable");

    my $inner = MakeInnerZip($pubkeydata,$mfzfile,$innertime, @files);

    my $signed = SignString($privkeyfile, $inner);
#    WriteWholeFile($mfzfile,MFZRUN_HEADER.$signed.$inner,0644);
    my $outer = MFZRUN_HEADER.MakeOuterZip($signed,$inner,undef);

    my $cdmmap = MakeCDMMap($regnum,$slotnum,$stamptime,$mfzfile,$privkeyfile,$outer,$innertime,$label);

    WriteWholeFile($mfzpath,$cdmmap.$outer,0644);
    return $mfzpath;
}

1;
