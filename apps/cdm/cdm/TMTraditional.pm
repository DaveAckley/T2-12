## Module stuff
package TMTraditional;
use strict;
use base 'TransferManager';
use fields qw(
    );

use Exporter qw(import);

our @EXPORT_OK = qw();
our %EXPORT_TAGS;

## Imports
use Constants qw(:all);
use DP qw(:all);
use T2Utils qw(:all);

## PRIVATE CLASS DATA

my $seqno = 0;

## Methods
sub new {
    my ($class,$cdm) = @_;
    defined $cdm or die;
    my $self = fields::new($class);
    $self->SUPER::new("trad",$cdm);
    $self->defaultInterval(-20); # Run about every 10 seconds if nothing happening
    $self->{mDirMgr} = $cdm->{mCompleteAndVerifiedContent} or die;

    return $self;
}

use Data::Dumper;

##OVERRIDE
sub handleAnnouncement {
    my __PACKAGE__ $self = shift;
    my PacketCDM_F $pkt = PacketCDM_F->assertValid(shift);
    my CDM $cdm = $self->{mCDM} or die;

    my $contentName = $pkt->{mName};

    ## STEP 0: Check if exact match in common
    my DMCommon $dmc = $cdm->getDMCommon() or die;
    my MFZManager $cmgr = $dmc->getMFZMgr($contentName); # or undef
    if (defined $cmgr) {
        if ($pkt->matchesMFZ($cmgr)) {
            DPVRB("Don't need ${\$pkt->summarize()}, already have ${\$cmgr->getTag()}");
            return 1;
        } elsif (!$cmgr->obsoletedByParts($contentName, $pkt->{mInnerTimestamp})) {
            DPVRB("Don't need ${\$pkt->summarize()}, ${\$cmgr->getTag()} is newer");
            return 1;
        }
    }

    ## STEP 0.5: Check if deleted
    return DPVRB("Ignoring $contentName age $pkt->{mInnerTimestamp}, has been deleted")
        if $dmc->isDeleted($contentName,$pkt->{mInnerTimestamp});

    ## STEP 1: Check if already in pending
    my DMPending $dmp = $cdm->getDMPending() or die;
    my MFZManager $pmgr = $dmp->getMFZMgr($contentName); # or undef
    if (defined $pmgr) {
        if ($pkt->matchesMFZ($pmgr)) {
            DPVRB("Don't need ${\$pkt->summarize()}, already have ${\$pmgr->getTag()}");
            DPSTD("XXX CONSIDER ADDING ANOTHER SOURCE FOR ".$pmgr->getTag());
            return 1;
        } elsif (!$pmgr->obsoletedByParts($contentName, $pkt->{mInnerTimestamp})) {
            DPVRB("Don't need ${\$pkt->summarize()}, ${\$pmgr->getTag()} is newer");
            return 1;
        }
    } else {
        DPSTD("XXX DMP mgrs ($contentName) :".join(", ",keys %{$dmp->{mMFZManagers}}));
        DPSTD("XXX DMP vals ($contentName) :".join(", ",values %{$dmp->{mMFZManagers}}));
    }

    ## STEP 2: Create in pending and TransferManager client
    $pmgr = $dmp->newContent($contentName);
    my $theirseqno = $pkt->populateMFZMgr($pmgr);
    my $sku = $pmgr->generateSKU($theirseqno);
    $pmgr->createEmptyFile();
    # TMTrad client data is: [DIR8, CN, SKU, SEQNO, MFZMGR]
    my $rec = TransferManager::createMetadataRec($pkt->getDir8(),$contentName,$sku,$theirseqno,$pmgr);
    DPSTD("${\FUNCNAME} rec [".join(", ",@{$rec})."]");
    $self->storeMetadata($rec);
    DPSTD("Starting receive of $contentName (SKU $sku) from ${\getDir8Name($pkt->getDir8())}");
    $self->requestChunkFrom($self->getMetadata($pkt->getDir8(),$contentName));
}

## CLASS METHOD
sub hack16 {
    my $str = shift;
    my $h = 0xfeed;
    for my $i (0 .. (length ($str) - 1)) {
        $h = (($h<<1)^ord(substr($str,$i,1))^($h>>11))&0xffff;
    }
    return chr(($h>>8)&0xff).chr($h&0xff);
}

sub sendDataChunk {
    my __PACKAGE__ $self = shift;
    my PacketCDM_C $pkt = PacketCDM_C->assertValid(shift);
    my CDM $cdm = $self->{mCDM} or die;
    my $sku = $pkt->{mSKU};
    my $rec = $self->getMetadataK2(DIR8_SERVER, $sku);
    return DPSTD("${\FUNCNAME} No server metadata sku($sku), ignoring ${\$pkt->summarize()}")
        unless defined $rec;
    my ($dir8,$cn,$recsku,$mgr,$announcepkt) = @{$rec};
    my $startIdx = $pkt->{mCurrentLength};
    DPSTD("Starting send of $cn (SKU $sku) to ${\getDir8Name($pkt->getDir8())}")
        if $startIdx == 0;
    my $data = $mgr->readDataFrom($startIdx);
    my PacketCDM_D $dpkt = PacketCDM_D->new();
    $dpkt->{mSKU} = $sku;
    $dpkt->{mStartingIndex} = $startIdx;
    $dpkt->{mData} = $data;
    $dpkt->{mHack16} = hack16($data);
    $dpkt->setDir8($pkt->getDir8());
    my $pio = $self->{mCDM}->getPIO();
    return $dpkt->sendVia($pio);
}
    
sub handleDataChunk {
    my __PACKAGE__ $self = shift;
    my PacketCDM_D $pkt = PacketCDM_D->assertValid(shift);
    my CDM $cdm = $self->{mCDM} or die;

    my $check16 = hack16($pkt->{mData});
    if ($pkt->{mHack16} ne $check16) {
        DPSTD("CHECKSUM FAILURE DROPPING ${\$pkt->summarize()}");
        return;
    }
    my $sku = $pkt->{mSKU};
    my $d9 = $pkt->getDir8();
    my $rec = $self->getMetadataK2($d9, $sku);
    return DPSTD("No metadata for dir8($d9) sku($sku), ignoring")
        unless defined $rec;
    my ($dir8,$cn,$recsku,$seqno,$mgr) = @{$rec};
    die unless $recsku eq $sku;
    my $curlen = $mgr->getCurrentLength();
    if ($curlen == $pkt->{mStartingIndex}) {
        $mgr->appendDataTo($pkt->{mData});
        if ($mgr->getCurrentLength() < $mgr->{mFileTotalLength}) {
            $self->requestChunkFrom($rec);
        } else {
            DPSTD("Received last of $cn (SKU $sku) from ${\getDir8Name($d9)}");
            $self->considerPendingRelease($mgr);
        }
    } else {
        DPSTD("${\FUNCNAME}: HANDLE $curlen != $pkt->{mStartingIndex}");
    }
}

sub considerPendingRelease {
    my __PACKAGE__ $self = shift or die;
    my MFZManager $pmgr = shift or die;
    my $cn = $pmgr->{mContentName};
    my DMCommon $dmc = $self->getCDM()->{mCompleteAndVerifiedContent};
    my MFZManager $cmgr = $dmc->getMFZMgr($cn);

    my $existing = defined($cmgr);
    my $storeable = !$existing || $cmgr->obsoletedByVerified($pmgr);

    my $ok = $pmgr->loadCnVMFZ() or 0;

    # Don't promote deleted files
    if ($ok && $dmc->isDeleted($cn,$pmgr->{mFileInnerTimestamp})) {
        DPSTD("$cn as of $pmgr->{mFileInnerTimestamp} is DELETED");
        $ok = 0;
    }

    if (!$ok) {
        DPSTD("${\$pmgr->getTag()} failed verification");
        $self->forgetMFZMgr($pmgr);
        $pmgr->destructDelete();
        return;
    }
    DPSTD("${\FUNCNAME} cn($cn) ok($ok) existing($existing) storeable($storeable)");
    if ($storeable) {
        if ($existing) {
            $self->forgetMFZMgr($cmgr);
            $cmgr->destructDelete();
        }
        $dmc->takeMFZAndFile($pmgr);
        DPSTD("--------${\$self->getTag()} RELEASED $cn--------");
        my $hkm = $self->{mCDM}->{mHookManager};
        $hkm->runHookIfAny(HOOK_TYPE_RELEASE,$pmgr); # now cmgr really
    }
}

sub requestChunkFrom {
    my __PACKAGE__ $self = shift or die;
    my $rec = shift or die;
    my ($dir8,$cn,$sku,$seqno,$mgr) = @{$rec};
    my $curlen = $mgr->getCurrentLength();
    if ($curlen == $mgr->{mFileTotalLength}) {
        return DPSTD("${\FUNCNAME}: HANDLE FILE COMPLETE");
    }
    my $pkt = PacketCDM_C->new();
    $pkt->setDir8($dir8);
    $pkt->{mCurrentLength} = $curlen;
    $pkt->{mSKU} = $sku;
    my $pio = $self->{mCDM}->getPIO();
    return $pkt->sendVia($pio);
}

sub update {
    my ($self) = @_;
    return 1 if $self->SUPER::update();

    my ($mfzmgr,$ngbmgr) = $self->selectPair();  # Weighted however..
    return 0 unless defined $mfzmgr and defined $ngbmgr;

    my $contentname = $mfzmgr->{mContentName};

    ## SERVER METADATA IS [8 cn sku mgr tradannouncepkt];
    my $od = $self->getMetadata(DIR8_SERVER,$contentname); 
    if (!defined($od) || $od->[3] != $mfzmgr) {
        # Need to (re)build od if possible
        return 0 unless $mfzmgr->mfzState() >= MFZ_STATE_CCNV; # not ready yet
        my $thisseqno = ++$seqno;
        my $sku = $mfzmgr->generateSKU($thisseqno);

        my $announce = $mfzmgr->createTraditionalAnnouncement($thisseqno);
        $od = TransferManager::createMetadataRec(DIR8_SERVER, $contentname, $sku, $mfzmgr, $announce);
        DPSTD("${\FUNCNAME} rec [".join(", ",@{$od})."] DDAND SKU($sku)");
        $self->storeMetadata($od);
    }
    my $pkt = $od->[4];
    $pkt->setDir8($ngbmgr->{mDir8}); # Modifies stored packet but we always do before use
    my $pio = $ngbmgr->getPIO();
    $pkt->sendVia($pio);
    return 1;
}

1;
