## Module stuff
package Hooks;
use strict;

use Exporter qw(import);

our @EXPORT_OK = qw(installHooks);
our %EXPORT_TAGS;

## Imports
use Fcntl;
use File::Temp qw(tempdir);

use Constants qw(:all);
use DP qw(:all);
use T2Utils qw(:all);
use HookManager qw(:actions);

my %cdmdTargetDirs = (
    'cdmd-MFM.mfz' => "/home/t2",
    'cdmd-T2-12.mfz' => "/home/t2",
    );

##VIRTUAL METHOD
sub run {
    my __PACKAGE__ $self = shift or die;
    my MFZManager $mgr = shift or die;
    my HookManager $rlm = shift or die;
    die "NOT OVERRIDDEN";
}

sub getTmpDirPrefix {
    return "cdmhook";
}

##CLASS METHOD
sub installSetup {
    my MFZManager $mfzmgr = shift or die;
    my $fname = $mfzmgr->{mContentName};
    if ($fname !~ /^cdmd-([^.]+)[.]mfz$/) {
        DPSTD("INSTALL '$fname': Malformed filename, ignoring");
        return;
    }
    my $baseName = $1;
    my $dirName = $cdmdTargetDirs{$fname};
    if (!defined $dirName) {
        DPSTD("INSTALL '$fname': No CDMD target, ignoring");
        return;
    }
    DPSTD("INSTALL found candidate $baseName -> $dirName");
    my $tagFileName = "$dirName/$fname-cdm-install-tag.dat";
    my $innerTimestamp = $mfzmgr->{mFileInnerTimestamp};
    if (-r $tagFileName) {
        open my $fh,'<',$tagFileName or die "Can't read $tagFileName: $!";
        my $line = <$fh>;
        close $fh or die "close $tagFileName: $!";
        $line ||= "";
        chomp $line;
        if ($line !~ /^([0-9]+)$/) {
            DPSTD("INSTALL Ignoring malformed $tagFileName ($line)");            
        } else {
            my $currentTimestamp = $1;
            if ($innerTimestamp == $currentTimestamp) {
                DPSTD("INSTALL $baseName: We are up to date; nothing to do");
                return;
            }
            if ($innerTimestamp < $currentTimestamp) {
                DPSTD("INSTALL $baseName: Candidate appears outdated ($innerTimestamp vs $currentTimestamp)");
                DPSTD("INSTALL $baseName: NOT INSTALLING. Delete $tagFileName to allow this install");
                return;
            }
        }
        DPSTD("INSTALL $tagFileName -> INSTALLING UPDATE");
    } 
    return ($fname, $baseName, $dirName, $tagFileName, $innerTimestamp);
}

##CLASS METHOD
sub installUnpack {
    my ($cdm, $fname, $baseName, $dirName, $tagFileName, $innerTimestamp) = @_;

    my $baseDir = $cdm->{mBaseDirectory};
    my DMCommon $dmc = $cdm->{mCompleteAndVerifiedContent};
    my $commonPath = $dmc->{mDirectoryPath};

    DPSTD("${\FUNCNAME} bd $baseDir cp $commonPath");

    ### DO UNPACK
    DPSTD("INSTALL $baseName: Starting install");
    my $tmpDirName = "$dirName/$baseName-cdm-install-tmp";
    DPSTD("INSTALL $baseName: (1) Clearing $tmpDirName");

    return unless runCommandWithSync("rm -rf $tmpDirName","INSTALL $baseName: ERROR");
    return unless runCommandWithSync("mkdir -p $tmpDirName","INSTALL $baseName: ERROR");

    my $mfzPath = "$commonPath/$fname";
    DPSTD("INSTALL $baseName: (2) Unpacking $mfzPath");

    return unless runCommandWithSync("${\PATH_PROG_MFZRUN} -kd $baseDir $mfzPath unpack $tmpDirName","INSTALL $baseName: ERROR");

    DPSTD("INSTALL $baseName: (3) Finding tgz");
    my $tgzpath;
    {
        my $cmd = "find $tmpDirName -name '*.tgz'";
        my $output = `$cmd`;
        chomp $output;
        DPSTD("INSTALL $baseName: (3.1) GOT ($output)");
        my @lines = split("\n",$output);
        my $count = scalar(@lines);
        if ($count != 1) {
            DPSTD("INSTALL $baseName: ABORT: FOUND $count LINES");
            return;
        }
        $tgzpath = $lines[0];
    }
    my $targetSubDir = "$tmpDirName/tgz";
    DPSTD("INSTALL $baseName: (4) Clearing '$targetSubDir'");
    return unless runCommandWithSync("rm -rf $targetSubDir","INSTALL $baseName: ERROR");
    return unless runCommandWithSync("mkdir -p $targetSubDir","INSTALL $baseName: ERROR");

    DPSTD("INSTALL $baseName: (5) Unpacking '$tgzpath' -> $targetSubDir");
    my $initialBaseNameDir;
    return unless runCommandWithSync("tar xf $tgzpath -m --warning=no-timestamp -C $targetSubDir","INSTALL $baseName: ERROR");

    $initialBaseNameDir = "$targetSubDir/$baseName";
    if (!(-r $initialBaseNameDir && -d $initialBaseNameDir)) {
        DPSTD("INSTALL $baseName: (5.1) ABORT: '$initialBaseNameDir' not readable dir");
        return;
    }

    return ($tmpDirName, $mfzPath, $tgzpath, $targetSubDir, $initialBaseNameDir);
}

sub installCDMD { # return undef unless install actually happened
    my MFZManager $mfzmgr = shift or die;
    my CDM $cdm = $mfzmgr->getCDM();

    my @args = installSetup($mfzmgr);
    return if scalar(@args) == 0;  # Something went wrong, or nothing to do
    my ($fname, $baseName, $dirName, $tagFileName, $innerTimestamp) = @args;

    my @moreargs = installUnpack($cdm, $fname, $baseName, $dirName, $tagFileName, $innerTimestamp );
    return if scalar(@moreargs) == 0;
    my ($tmpDirName, $mfzPath, $tgzpath, $targetSubDir, $initialBaseNameDir) = @moreargs;
    
    ### DO FULL DIR MOVE REPLACEMENT
    my $prevDirName = "$dirName/$baseName-cdm-install-prev";
    DPSTD("INSTALL $baseName: (6) Clearing $prevDirName");

    return unless runCommandWithSync("rm -rf $prevDirName","INSTALL $baseName: ERROR");

    return unless runCommandWithSync("mkdir -p $prevDirName","INSTALL $baseName: ERROR");

    my $finalDirName = "$dirName/$baseName";
    DPSTD("INSTALL $baseName: (7) Moving $finalDirName to $prevDirName");
    return unless runCommandWithSync("mv $finalDirName $prevDirName","INSTALL $baseName: ERROR");

    DPSTD("INSTALL $baseName: (8) Moving $initialBaseNameDir to $finalDirName");
    return unless runCommandWithSync("mv $initialBaseNameDir $finalDirName","INSTALL $baseName: ERROR");

    DPSTD("INSTALL $baseName: (9) Tagging install $tagFileName -> $innerTimestamp");
    {
        my $fh;
        if (!(open $fh,'>',$tagFileName)) {
            DPSTD("INSTALL $baseName: WARNING: Can't write $tagFileName: $!");
            return;
        }
        print $fh "$innerTimestamp\n";
        close $fh or die "close $tagFileName: $!";
    } 

    DPSTD("INSTALLED '$fname'");
    return 1;
}

sub makeTmpDir {
    my $prefix = getTmpDirPrefix();
    my $template = "$prefix-XXXXX";
    my $cleanup = 1;

    $cleanup = 0 
        if DPANYFLAGS(DEBUG_FLAG_SAVE_TMP_DIRS);

    my $destdir =
        tempdir( $template,
                 TMPDIR => 1,
                 CLEANUP => $cleanup
        );
    return $destdir;
}

sub unpackToTempDir {
    my MFZManager $mgr = shift or die;
    my CDM $cdm = $mgr->getCDM();
    my $basedir = $cdm->getBaseDirectory();
    my $destdir = makeTmpDir();
    my $path = $mgr->getPathToFile() or die;

    my $cmd = "${\PATH_PROG_MFZRUN} -kd $basedir $path unpack $destdir";
    runCommandWithSync($cmd,"unpackDeleteds");
    return $destdir;
}

### DEFINE HOOKS HERE
sub CDM_DELETEDS_MFZ_LOAD_HOOK {
    my MFZManager $mgr = shift or die;
    my $hooktype = shift or die;
    die unless $hooktype eq HOOK_TYPE_LOAD;
    
    my HookManager $rlm = shift or die;

    my $cn = $mgr->{mContentName};
    $cn eq CDM_DELETEDS_MFZ or die;
    
    # Unpack it, then for the path used to pack the payload
    my $destdir = unpackToTempDir($mgr);
    my $tmpprefix = getTmpDirPrefix();
    DPSTD("Unpacked to $destdir");
    my @paths = glob "$destdir/tmp/*/cdm-deleteds.map";

    my $deletedsFilePath = shift @paths;

    return DPSTD("'$destdir' problem, can't update deleteds")
        unless defined $deletedsFilePath;

    DPSTD("Loading $deletedsFilePath");
    open(HDL, "<", $deletedsFilePath)
        or die "Can't read $deletedsFilePath: $!";
    my @records;
    while (<HDL>) {
        chomp;
        my @fields = split(/\s+/,$_);
        scalar(@fields) == 4 or die "Bad fmt '$_'";
        my $filename = deHexEscape($fields[0]);
        my $length = $fields[1];
        my $checksum = $fields[2];
        my $timestamp = $fields[3];
        push @records, [$filename, $length, $checksum,$timestamp];
    }
    close(HDL) or die "Closing $deletedsFilePath: $!";
    ## OK they all came in.  Update DMCommon
    my $cdm = $mgr->getCDM();
    my $dmc = $cdm->{mCompleteAndVerifiedContent};

    ## FLUSH EXISTING MAP
    $dmc->{mDeletedsMap} = { };
    for my $rec (@records) {
        $dmc->{mDeletedsMap}->{$rec->[0]} = $rec;
        DPSTD("R.I.P. $rec->[0] DEAD AS OF $rec->[3]");
    }
    DPSTD("${\$dmc->getTag()} deleteds map loaded");
}

sub CDMD_T2_12_MFZ_RELEASE_HOOK {
    my MFZManager $mgr = shift or die;
    my $hooktype = shift or die;
    die unless $hooktype eq HOOK_TYPE_RELEASE;
    
    my HookManager $rlm = shift or die;

    my $cn = $mgr->{mContentName};
    $cn eq CDMD_T2_12_MFZ or die;
    
    return "DONE" unless defined installCDMD($mgr);

    DPSTD("RUNNING T2-12 MAKE INSTALL");
    runCommandWithSync("make -C /home/t2/T2-12 -k install","T2-12: make install: ERROR");
    return undef; # Continue with other hook actions
}

sub CDMD_MFM_MFZ_RELEASE_HOOK {
    my MFZManager $mgr = shift or die;
    my $hooktype = shift or die;
    die unless $hooktype eq HOOK_TYPE_RELEASE;
    
    my HookManager $rlm = shift or die;

    my $cn = $mgr->{mContentName};
    $cn eq CDMD_MFM_MFZ or die;
    
    return "DONE" unless defined installCDMD($mgr);

    return undef; # Continue with other hook actions
}

##CLASS METHOD
sub installHooks {
    my CDM $cdm = shift or die;
    my HookManager $rlm = $cdm->{mHookManager} or die;

    ### DECLARE NEW HOOKS HERE
    $rlm->registerHookActions(HOOK_TYPE_LOAD, CDM_DELETEDS_MFZ,
                              \&CDM_DELETEDS_MFZ_LOAD_HOOK);
    $rlm->registerHookActions(HOOK_TYPE_RELEASE, CDMD_T2_12_MFZ,
                              \&CDMD_T2_12_MFZ_RELEASE_HOOK,
                              \&HOOK_ACTION_RESTART_CDM);
    $rlm->registerHookActions(HOOK_TYPE_RELEASE, CDMD_MFM_MFZ,
                              \&CDMD_MFM_MFZ_RELEASE_HOOK,
                              \&HOOK_ACTION_RESTART_MFMT2);
}


1;
