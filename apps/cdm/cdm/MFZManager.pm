## Module stuff
package MFZManager;
use strict;
use base 'TimeoutAble';
use fields qw(
    mContentName
    mDirectoryManager
    mState
    mVerificationStatus
    mFileModificationTime
    mFileTotalLength
    mFileTotalChecksum
    mFileInnerLength
    mFileInnerTimestamp
    mFileInnerChecksum
    mFilePipelineAnnouncePacket
    mAnnouncedContentName
    mPrefixLengthAvailable
    mXsumMap
    mXsumDigester
    );

use Exporter qw(import);

our @EXPORT_OK = qw();
our %EXPORT_TAGS;

## Imports
use DP qw(:all);
use Constants qw(:all);
use T2Utils qw(:math :fileops);
use DMCommon;

## PRIVATE CLASS VARS

## Methods
sub new {
    my ($class,$name,$cdm) = @_;
    defined $cdm or die;
    my $self = fields::new($class);
    $self->SUPER::new("MFZMgr:$name",$cdm);

    $self->{mContentName} = $name;
    $self->{mDirectoryManager} = undef;
    $self->{mState} = MFZ_STATE_INIT;
    $self->{mVerificationStatus} = -1; # Not tried
    $self->{mFileModificationTime} = undef;
    $self->{mFileTotalLength} = -1;
    $self->{mFileTotalChecksum} = "";
    $self->{mFileInnerLength} = -1;
    $self->{mFileInnerTimestamp} = -1;
    $self->{mFileInnerChecksum} = "";
    $self->{mFilePipelineAnnouncePacket} = undef;
    $self->{mAnnouncedContentName} = undef;
    $self->{mPrefixLengthAvailable} = 0;
    $self->{mXsumMap} = [];
    $self->{mXsumDigester} = Digest::SHA->new(256);

    $self->{mCDM}->getTQ()->schedule($self);
    $self->defaultInterval(-20); # Run about every 10 seconds if nothing happening

    return $self;
}

sub createTraditionalAnnouncement {
    my $self = shift;
    my $seqno = shift or die;
    my $pkt = PacketCDM_F->new();
    $pkt->{mName} = $self->{mContentName};
    $pkt->{mLength} = $self->{mFileTotalLength};
    $pkt->{mChecksum} = $self->{mFileTotalChecksum};
    $pkt->{mInnerTimestamp} = $self->{mFileInnerTimestamp};
    $pkt->{mSeqno} = $seqno;
    return $pkt;
}

sub mfzState {
    my $self = shift;
    if (defined $_[0]) {
        my $new = shift;
#        print $self->getTag().": $self->{mState} => $new". Carp::longmess();
        $self->{mState} = $new;
    }
    return $self->{mState};
}

##CLASS METHOD
sub seekVerificationInfoForPath {
    my $mfzpath = shift or die;
    my $basedir = shift or die;
    return DPSTD("$mfzpath: Bad path")
        unless -r $mfzpath && -f $mfzpath;

    my $modtime = -M $mfzpath;
    my $totallength = -s $mfzpath;
    my $cmd = "echo Q | ".PATH_PROG_MFZRUN." -kd $basedir $mfzpath VERIFY";
    DPSTD("DO '$cmd'");
    my $output = `$cmd`;

    if ($output =~ /.*?signer handle '(:?[a-zA-Z][-., a-zA-Z0-9]{0,62})' is not recognized!/) {
        my $badhandle = $1;
        return DPSTD("Unrecognized handle '$badhandle' in $mfzpath");
    }

    if ($output !~ s/^SIGNING_HANDLE \[(:?[a-zA-Z][-., a-zA-Z0-9]{0,62})\]//m) {
        return DPSTD("Handle of $mfzpath not found in '$output'");
    }
    my $handle = $1;

    if ($handle ne "t2-keymaster-release-10") { # Note that mfzrun verifies handle against local pubkeys
        return DPSTD("Handle '$handle' of $mfzpath is unappealing");
    }

    if ($output !~ s/^INNER_TIMESTAMP \[(\d+)\]//m) {
        return DPSTD("Timestamp of $mfzpath not found in '$output'");
    }
    my $timestamp = $1;
    DPSTD(" $mfzpath: $handle => $timestamp");

    return ($mfzpath, $handle, $timestamp, $totallength, $modtime);
}

sub loadCnVMFZ {
    my ($self) = @_;

    $self->{mVerificationStatus} = -1; # Forget whatever we might have known

    my $basedir = $self->{mCDM}->getBaseDirectory();
    my $mfzpath = $self->getPathToFile();
    return DPSTD("$mfzpath: Bad path")
        unless -r $mfzpath && -f $mfzpath;

    $self->{mFileModificationTime} = -M $mfzpath;

    my $totallength = -s $mfzpath;
    my $cmd = "echo Q | ".PATH_PROG_MFZRUN." -kd $basedir $mfzpath ANNOUNCE";
    DPSTD("DO '$cmd'");
    my $output = `$cmd`;
    my ($packet,$verifoutput) = unpack(ANNOUNCE_UNPACK_OUTPUT_FORMAT,$output);

    return DPSTD("$mfzpath: Bad announcement length ".length($packet))
        unless length($packet) == ANNOUNCE_PACKET_LENGTH;

    my (undef, undef, undef,
        $version,$innertime,$innerlength,$regnum,$innerchecksum,$contentname)
        = unpack(ANNOUNCE_PACK_DATA_FORMAT, $packet);
    $contentname =~ s/\x00+$//;
    my $filestem = $self->{mContentName};
    $filestem =~ s/[.]mfz$//;
    return DPSTD("Mismatched names (internal) $contentname vs (external) $filestem")
        unless $contentname eq $filestem;
    $self->{mAnnouncedContentName} = $contentname;
    return DPSTD("Inconsistent lengths (internal) $innerlength vs (external) $totallength")
        unless $totallength > $innerlength;
    $self->{mFileTotalLength} = $totallength;
    $self->{mFileTotalChecksum} = checksumWholeFile($mfzpath);
    $self->{mFileInnerLength} = $innerlength;
    $self->{mFileInnerTimestamp} = $innertime;
    $self->{mFileInnerChecksum} = $innerchecksum;
    $self->{mFilePipelineAnnouncePacket} = $packet;
    $self->buildXsumMap();
    DPSTD("loadCnVMFZ ".$self->getTag()." ($version,$innertime,$totallength,$innerlength,$regnum,$contentname)");
    $self->mfzState(MFZ_STATE_CCNV);
    $self->{mVerificationStatus} = 1; # We like
    return 1;
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

sub insertInXsumMap {
    my ($self, $filepos, $xsum) = @_;
    defined $xsum or die;
    my $aref = $self->{mXsumMap};
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

sub findXsumInRange {
    my ($self, $lo, $hi) = @_;
    return undef if $lo > $hi;
    my $aref = $self->{mXsumMap};
    my $loidx = indexOfLowestAtLeast($aref, $lo);
    my $hiidx = indexOfLowestAtLeast($aref, $hi+1);
    return ($loidx != $hiidx) ? ($aref->[2*$loidx], $aref->[2*$loidx+1]) : undef;
}

use Data::Dumper;

sub buildXsumMap {
    my ($self) = @_;
    $self->{mXsumMap} = [];
    my $digester = $self->{mXsumDigester};
    my $path = $self->getPathToFile();

    my $XSUM_PIECE_COUNT = 100;
    my $filelen = $self->{mFileTotalLength} or die;
    my $chunksize = max(1<<12,ceiling($filelen/$XSUM_PIECE_COUNT));
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
            $self->insertInXsumMap($position, $digester->clone->b64digest()); # food dog own eat
#            push @{$plinfo->{xsumMap}}, $position, $digester->clone->b64digest();
            $lastposition = $position;
        }
#        DPSTD("$position $count $chunksize =".$plinfo->{xsumMap}->{$position});
        last if $count == 0;
    }
    close HDL or die "Can't close $path: $!";
#    print Dumper(\$self);
}

sub createEmptyFile {
    my __PACKAGE__ $self = shift or die;
    my $path = $self->getPathToFile();
    if (!open(HDL,">",$path)) {
        DPSTD("CAN'T INIT $path: $!");
        return undef;
    }
    close HDL or die "Can't close $path:$!";
    $self->mfzState(MFZ_STATE_FILE)
        if $self->mfzState() < MFZ_STATE_FILE;
    return 1;
}

sub getCurrentLength {
    my __PACKAGE__ $self = shift or die;
    my $path = $self->getPathToFile();
    return -s $path;
}

sub isKnownVerified {
    my __PACKAGE__ $self = assertMFZLive(shift);
    my $status = $self->{mVerificationStatus};
    return $status if $status >= 0;
    
}

##CLASS METHOD
sub generateSKUFromParts {
    my ($filename, $checksum, $timestamp, $seqno) = @_;
    my $sku = sprintf("%s%02x%02x%03d%s",
                      substr($filename,0,1),
                      ord(substr($checksum,0,1)),
                      ord(substr($checksum,1,1)),
                      $timestamp%1000,
                      lexEncode($seqno));
    DPSTD("SKU($sku) <= $filename");
    return $sku;
}

sub generateSKU {
    my __PACKAGE__ $self = shift or die;
    my $seqno = shift;
    return generateSKUFromParts($self->{mContentName},$self->{mFileTotalChecksum},$self->{mFileInnerTimestamp},$seqno);
}

sub readDataFrom {
    my __PACKAGE__ $self = assertMFZLive(shift);
    my $startingIndex = shift;
    my $filelen = $self->getCurrentLength();
    my $maxWanted = max(0, min(MAX_D_TYPE_DATA_LENGTH, $filelen - $startingIndex));
    my $path = $self->getPathToFile();
    open my $fh, '<', $path or die "Can't open $path: $!";
    sysseek $fh, $startingIndex, 0 or die "Can't seek $path to $startingIndex: $!";
    my $data;
    my $read = sysread $fh, $data, $maxWanted;
    if ($read != $maxWanted) {
        DPSTD("Wanted $maxWanted at $startingIndex of $path, but got $read");
    }
    close $fh or die "Can't close $path: $!";
    return $data;
}

sub getPathToFile {
    my __PACKAGE__ $self = assertMFZLive(shift);
    my $path = $self->{mDirectoryManager}->{mDirectoryPath};
#    DPSTD("${\FUNCNAME} $self $self->{mDirectoryManager}");
    defined $path or die;
    my $cname = $self->{mContentName};
    my $filepath = "$path/$cname";
    return $filepath;
}

##CLASS METHOD
sub assertMFZLive {
    my __PACKAGE__ $self = shift or die "Undef passed as MFZManager";
    die "Attempt to access dead MFZManager ($self)" unless isLive($self);
    $self;
}

sub isLive {
    my __PACKAGE__ $self = shift or return 0;
    $self->isa(__PACKAGE__) or return 0;
    $self->mfzState() < MFZ_STATE_DEAD or return 0;
    return 1;
}

## SEE ../notes/202008201554-notes.txt:134:
sub destructDetach {
    my __PACKAGE__ $self = assertMFZLive(shift);
    DPSTD("${\FUNCNAME} ${\$self->{mContentName}}");
    $self->{mDirectoryManager}->removeMFZMgr($self);
    $self->mfzState(MFZ_STATE_DEAD);
    $self->unschedule();
}

sub destructDelete {
    my __PACKAGE__ $self = assertMFZLive(shift);
    my $path = $self->getPathToFile();
    DPSTD("${\FUNCNAME} $path");
    $self->destructDetach();
    # WARNING: $self is now MFZ_STATE_DEAD
    if (defined $path) {
        DPSTD("Couldn't delete '$path': $!")
            unless unlink $path;
    }
}

sub obsoletedByVerified { # If mfzrun VERIFY likes it
    my __PACKAGE__ $self = assertMFZLive(shift);
    my __PACKAGE__ $othr = assertMFZLive(shift);
    return $self->obsoletedByParts($othr->{mContentName},$othr->{mFileInnerTimestamp});
}

sub obsoletedByParts {
    my __PACKAGE__ $self = assertMFZLive(shift);
    my $cn = shift or die;
    my $innertimestamp = shift or die;
    return 0 if $self->{mContentName} ne $cn;
    return 0 if $self->{mFileInnerTimestamp} >= $innertimestamp;
    return 1;
}

sub appendDataTo {
    my __PACKAGE__ $self = assertMFZLive(shift);
    die unless $self->mfzState() == MFZ_STATE_FILE;
    my $data = shift;
    my $datalen = length($data);
    return if $datalen == 0;
    my $curlen = $self->getCurrentLength();
    return DPSTD("${\FUNCNAME} ignoring $datalen bytes")
        if $curlen == $self->{mFileTotalLength};

    my $path = $self->getPathToFile();
    open(HDL,">>",$path) or die "Can't append to $path: $!";
    print HDL $data;
    close HDL or die "Can't close $path: $!";
#    DPSTD("${\FUNCNAME} $curlen + $datalen");
}

sub update {
    my __PACKAGE__ $self = assertMFZLive(shift);
    DPSTD("${\FUNCNAME} $self->{mState}");
    if (!$self->isLive()) {
        $self->unschedule();
        return;
    }

    my $dm = $self->{mDirectoryManager};
    if ($dm->{mDirectoryName} eq SUBDIR_COMMON) {
        my DMCommon $dmc = $dm;
        my $cn = $self->{mContentName};
        my $its = $self->{mFileInnerTimestamp};
        if ($dmc->isDeleted($cn,$its)) {
            DPSTD("$cn at $its: ONO I'M DELETED!");
            $self->destructDelete();
            return;
        }
    }
    
    my $filepath = $self->getPathToFile();
    if ($self->mfzState() == MFZ_STATE_INIT) {
        if (-R $filepath && -f $filepath) {
            $self->mfzState(MFZ_STATE_FILE);
            $self->{mFileModificationTime} = -M $filepath;
        }
        $self->reschedule(-2);
        return;
    }

    unless (-R $filepath && -f $filepath) {
        DPSTD("$filepath gone or inaccessible, deleting mgr");
        $self->destructDetach();
        return;
    }

    # If we're CnV, we shouldn't change: Start over on modtime changes
    # Except, actually, at least if we're in common, we should
    # immediately try to reload the thing.  If we just delete
    # us-the-mgr, we're likely to just get another (old) copy of it
    # coming in from a ngb, before the DM notices it on its own.
    if ($self->mfzState() == MFZ_STATE_CCNV &&
        defined($self->{mFileModificationTime}) &&
        -M $filepath != $self->{mFileModificationTime}) {

        my $cn = $self->{mContentName};
        my $dm = $self->{mDirectoryManager};
        DPSTD("$filepath MODTIME CHANGE, deleting mgr");
        $self->destructDetach();
        DPSTD("Reacquiring $cn");
        $dm->newContent($cn);
        
        return;
    }

    if ($self->mfzState() == MFZ_STATE_FILE) {
        DPSTD($self->getTag().": NOW HUWHAT?");
    }
}

sub onTimeout {
    my __PACKAGE__ $self = assertMFZLive(shift);
    DPPushPrefix($self->getTag());
    $self->update();
    DPPopPrefix(); 
}

1;
