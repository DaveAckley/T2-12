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

##CLASS METHOD
sub runCommandWithSync {
    my ($btcmd,$errprefix) = @_;
    DPPushPrefix($errprefix) if defined $errprefix;
    `$btcmd && sync`; 
    my $ret = $?;
    DPSTD("'$btcmd' returned code $ret") if $ret;
    DPPopPrefix() if defined $errprefix;
    return $ret;
}

##CLASS METHOD
sub installHooks {
    my CDM $cdm = shift or die;
    my HookManager $rlm = $cdm->{mHookManager} or die;

    ### DECLARE NEW HOOKS HERE
    $rlm->registerHook(HOOK_TYPE_LOAD, CDM_DELETEDS_MFZ, \&CDM_DELETEDS_MFZ_LOAD_HOOK);
    
}


1;
