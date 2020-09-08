#!/usr/bin/perl -w  # -*- perl -*-
use strict;
use File::Basename;
use Cwd qw(abs_path);
use lib dirname (abs_path(__FILE__));
#use lib "/home/t2/MFM/res/perllib";

use MFZUtils qw(:all);
use Constants qw(:all);
use CDM;
use DP qw(:all);
use T2Utils qw(:all);

use PacketClasses;
use Hooks;

## Cleanliness stuff
use warnings FATAL => 'all';
$SIG{__DIE__} = sub {
    die @_ if $^S;
    require Carp; 
    Carp::confess ;
};

use Data::Dumper;
sub main {
    STDOUT->autoflush(1);
    DPSetFlags(DEBUG_FLAG_STACK_PREFIX|DEBUG_FLAG_STANDARD);
    DPSTD("$0 start");

#    my $cdm = CDM->new("./cdmDEBUG");
    my $cdm = CDM->new("/cdm"); # Go live
    $cdm->init();

#    DO_DEBUG_THING($cdm);
#    exit 1;

    my $dirsmgr = $cdm->getDirectoriesManager();
    my $dmc = $dirsmgr->getDMCommon();
    DPPushPrefix("Preloading $dmc->{mDirectoryName}");
    $dmc->loadAll();
    DPPopPrefix();

    $cdm->eventLoop();

    print "COUNT=".$cdm->update()."\n";

    exit 0;
}

sub DO_DEBUG_THING10 {
    my $cdm = shift;
    open HDL ,"<","zongannounce.pkt" or die;
    my $p;
    my $r = sysread HDL, $p, 200;
    print "$r\n";
    close HDL or die;
#    substr($p,100,1) = chr(0xf0);  # spoil packet in non-obvious way
    my $pkt = Packet::parse($p);
    die "error" unless defined($pkt);

    my $ret = $pkt->verifySignature($cdm);

    my $old = substr($pkt->{mRSASig},20,1);
    substr($pkt->{mRSASig},20,1) = chr(0xf0);  # spoil packet in non-obvious way
    my $ret2  = $pkt->verifySignature($cdm);

    substr($pkt->{mRSASig},20,1) = $old;       # restore what has been spoiled
    my $ret3  = $pkt->verifySignature($cdm);   # check idempotency

    die "PACKET SHOULD BE GOOD($ret)/BAD($ret2)/GOOD($ret3)";

    # my $fullpubkeypath = "/cdm/public_keys/t2%2dkeymaster%2drelease%2d10.pub";
    # my $fullpubstring = ReadWholeFile($fullpubkeypath);
    # my ($pubhandle, $pubkey) = SplitHandleFromKey($fullpubstring);
    # UDie("Bad format public key") unless defined $pubhandle;

    # my $rsapub = Crypt::OpenSSL::RSA->new_public_key($pubkey);
    # $rsapub->use_pkcs1_padding();
    # $rsapub->use_sha512_hash();

    # my $verified = $rsapub->verify($pkt->{mPayload},$pkt->{mRSASig});
    # die "XXX GOT VERIFIED ($verified) MORE";
}

sub DO_DEBUG_THING11 {
    my $cdm = shift;
    my $mfzref = LoadOuterMFZToMemory("/cdm/common/cdmd-T2-12.mfz");
    my @ret2 = LoadInnerMFZToMemory($mfzref);
}

sub DO_DEBUG_THING12 {
    my $cdm = shift or die;
    my $dirmgr = $cdm->{mCompleteAndVerifiedContent};
    my $mfzmgr = MFZManager->new("cdmd-T2-12.mfz",$cdm);
    $dirmgr->insertMFZMgr($mfzmgr);
    $mfzmgr->loadCnVMFZ();
}

sub DO_DEBUG_THING13 {
    my $cdm = shift or die;

    my $cmdirmgr = $cdm->{mCompleteAndVerifiedContent};
    my $mfzmgr = MFZManager->new("cdmd-T2-12.mfz",$cdm);
    $cmdirmgr->insertMFZMgr($mfzmgr);
    $mfzmgr->loadCnVMFZ();

    my $pipedirmgr = $cdm->{mInPipelineContent};
    my $mfzmgr2 = MFZManager->new("cdm-deleteds.mfz",$cdm);
    $pipedirmgr->insertMFZMgr($mfzmgr2);
    $mfzmgr2->loadCnVMFZ();

    my $tmppipe = $cdm->{mPipelineManager};
    $tmppipe->update();
}

sub DO_DEBUG_THING14 {
    my $cdm = shift or die;

    my $dirsmgr = $cdm->getDirectoriesManager();
    my $cmdirmgr = $dirsmgr->{mCompleteAndVerifiedContent};
    my $mfzmgr = MFZManager->new("cdmd-T2-12.mfz",$cdm);
    $cmdirmgr->insertMFZMgr($mfzmgr);
    $mfzmgr->loadCnVMFZ();

    my $tmppipe = $cdm->{mPipelineManager};

    my $hoodmgr = $cdm->{mNeighborhoodManager};
    my $semgr = $hoodmgr->ngbMgr(getDir6Number("SE"));
    my $spktstring = $tmppipe->createAnnouncementFor($mfzmgr,$semgr);

    my Packet $spkt = Packet::parse($spktstring);
    defined $spkt or die;
    $spkt->handleInbound($cdm);
}

sub DO_DEBUG_THING {
    my $cdm = shift or die;
    my $dirsmgr = $cdm->getDirectoriesManager();
    my $cmdirmgr = $dirsmgr->{mCompleteAndVerifiedContent};
    my $mfzmgr = MFZManager->new("cdmd-T2-12.mfz",$cdm);
    $cmdirmgr->insertMFZMgr($mfzmgr);
    $mfzmgr->loadCnVMFZ();

    my $pfpkt = $mfzmgr->{mFilePipelineAnnouncePacket};
    $pfpkt->setDir8(getDir8Number('SW'));
    $pfpkt->pack();
    my $pfpktstring = $pfpkt->{mPacketBytes};
    
    print length($pfpktstring);
    my $pfpkt2 = Packet::parse($pfpktstring);
    $pfpkt2->handleInbound($cdm);
}


main();
