## Module stuff
package TMPipeline;
use strict;
use base 'TransferManager';
use fields qw(
    );

use Exporter qw(import);

our @EXPORT_OK = qw();
our %EXPORT_TAGS;

## Imports
use T2Utils qw(:dirs);
use Constants qw(:all);
use DP qw(:all);
use PacketCDM_PF;
use PacketCDM_PR;

## Methods
sub new {
    my ($class,$cdm) = @_;
    defined $cdm or die;
    my $dirsmgr = $cdm->getDirectoriesManager();
    my $self = fields::new($class);
    $self->SUPER::new("ppln",$cdm);
    $self->defaultInterval(-20); # Run about every 10 seconds if nothing happening

    return $self;
}

sub requestPipelineChunkFrom {
    my __PACKAGE__ $self = shift or die;
    my $rec = shift or die;
    my ($dir8,$cn,$obtag,$mgr) = @{$rec};
    my $curlen = $mgr->getCurrentLength();
    if ($curlen == $mgr->{mFileTotalLength}) {
        return DPSTD("${\FUNCNAME}: HANDLE FILE COMPLETE XXX DO SOMETHING");
    }
    my $pkt = PacketCDM_PR->new();
    $pkt->setDir8($dir8);
    $pkt->{mFilePosition} = $curlen;
    $pkt->{mOutboundTag} = $obtag;
    my $pio = $self->{mCDM}->getPIO();
    return $pkt->sendVia($pio);
}

sub createPipelineEntry {
    my __PACKAGE__ $self = shift or die;
    my PacketCDM_PF $pfpkt = shift or die;

    my CDM $cdm = $self->{mCDM} or die;
    my DirectoriesManager $dm = $cdm->getDirectoriesManager() or die;

    my DMPipeline $dmp = $dm->getDMPipeline() or die;
    
    my $pmgr = $dmp->newContentStub($pfpkt);

    $pmgr->createEmptyFile();
    my ($dir8, $contentname, $outboundtag) =
        ($pfpkt->getDir8(), $pmgr->{mContentName}, $pfpkt->{mOutboundTag});

    # TMPipeline client data is: [DIR8, CN, OUTBOUNDTAG, MFZMGR]
    my $rec = TransferManager::createMetadataRec($dir8, $contentname, $outboundtag, $pmgr);

    DPSTD("${\FUNCNAME} rec [".join(", ",@{$rec})."]");
    $self->storeMetadata($rec);

    DPSTD("Starting receive of $contentname (tag $outboundtag) from ${\getDir8Name($pfpkt->getDir8())}");
    $self->requestPipelineChunkFrom($self->getMetadata($dir8,$contentname));

}

##OVERRIDE
sub handleAnnouncement {
    my __PACKAGE__ $self = shift;
    my CDM $cdm = $self->{mCDM} or die;
    my PacketCDM_PF $pfpkt = shift or die;
    my PacketCDM_S $spkt = $pfpkt->{mSPacket} or die;
    return DPSTD($@)
        unless $spkt->verifySignature($cdm); # Not already done?
    my $dirsmgr = $cdm->{mDirectoriesManager};
    my ($domdm,$dommfzmgr) = $dirsmgr->getDominantDM($spkt->getContentName());

    return DPSTD("Ignoring ".$pfpkt->summarize().", dominated by ".$dommfzmgr->getTag()
                 ." in ". $domdm->{mDirectoryName})
        if defined($dommfzmgr) && $dommfzmgr->{mFileInnerTimestamp} >= $spkt->{mInnerTimestamp};

    # If this announce is not dominated it's time to step up

    # Are we dominating an in-progress pipeline file?  It's possible.
    if (defined($domdm) && $domdm->{mDirectoryName} eq SUBDIR_PIPELINE) {
        DPSTD("Replacing dominated ".$dommfzmgr->getTag()." in ".$domdm->{mDirectoryName});
        $dommfzmgr->destructDelete();
    }
    $self->createPipelineEntry($pfpkt);
}

sub createAnnouncementFor {
    my __PACKAGE__ $self = shift or die;
    my MFZManager $mfzmgr = shift or die;
    my NeighborManager $ngbmgr = shift or die;
    my $pfpkt = $mfzmgr->createPipelineAnnouncement($ngbmgr->{mDir8});
    return $pfpkt;
}

sub makeAnnouncement {
    my __PACKAGE__ $self = shift or die;
    my MFZManager $mfzmgr = shift or die;
    my NeighborManager $ngbmgr = shift or die;
    my $pfpkt = $self->createAnnouncementFor($mfzmgr,$ngbmgr);
    my $pio = $ngbmgr->getPIO();
    $pfpkt->sendVia($pio);
}

sub maybeMakeAnnouncement {
    my __PACKAGE__ $self = shift or die;
    my $cdm = $self->{mCDM};
    my @dms = ($cdm->{mCompleteAndVerifiedContent}, $cdm->{mInPipelineContent});
    my ($mfzmgr,$ngbmgr) = $self->selectPair(@dms);  # Weighted however..
    return 0 unless defined $mfzmgr and defined $ngbmgr;
    return $self->makeAnnouncement($mfzmgr,$ngbmgr);
}

sub update {
    my __PACKAGE__ $self = shift or die;
    return 1 if $self->SUPER::update();
    return $self->maybeMakeAnnouncement();
}

1;
