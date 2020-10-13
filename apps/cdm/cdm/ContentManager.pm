## Module stuff
package ContentManager;
use strict;
use base 'TimeoutAble';
use fields qw(
    mInDir
    mInDirModTime
    mSSMap
    mDeletedMap
    );

use Exporter qw(import);

our @EXPORT_OK = qw();
our %EXPORT_TAGS;

use Digest::SHA;

use DP qw(:all);
use Constants qw(:all);
use T2Utils qw(:math :fileops);
use MFZUtils qw(:all);
use CDMap;
use PacketCDM_F;
use PacketCDM_C;
use DeletedMap;

# Task0: Get the existing MFZModel for $ss if any
sub getMFZModelForSSIfAny {
    my __PACKAGE__ $self = shift || die;
    my $ss = shift || die;
    my $slot = SSSlot($ss);
    my $ts = SSStamp($ss);
    my $map = $self->{mSSMap}->{$slot};
    return undef unless defined $map;
    return $map->{$ts};
}

sub pickImprovableMFZModel { # Return undef or an incomplete model with a usable server
    my __PACKAGE__ $self = shift || die;
    my $slot = pickOne(keys %{$self->{mSSMap}});
    return undef unless defined $slot;

    my @tss = sort {$b <=> $a} keys %{$self->{mSSMap}->{$slot}};
    for my $ts (@tss) {
        my $m = $self->{mSSMap}->{$slot}->{$ts};
        return $m if defined $m->selectServableD8();
    }
    return undef;
}

# Task1: Pick a random undominated MFZModel to announce or perhaps grow
sub pickUndominatedMFZModel {
    my __PACKAGE__ $self = shift || die;
    my $slot = pickOne(keys %{$self->{mSSMap}});
    return $self->getDominantMFZModelForSlot($slot,DOM_ONLY_MAPPED);
}

# Return undef if there is no known model for $slot, or return the
# dominant $slot model allowable according to $mode: Only complete
# models if DOM_ONLY_COMPLETE, or all models including
# non-announceable models if DOM_INCLUDE_ALL, or just announceable
# models if DOM_ONLY_MAPPED (or otherwise).
sub getDominantMFZModelForSlot {
    my __PACKAGE__ $self = shift || die;
    my $slot = shift;
    my $mode = shift || die;
    return undef unless defined $slot;
    my $model = undef;
    my @tss = sort {$b <=> $a} keys %{$self->{mSSMap}->{$slot}};
    for my $ts (@tss) {
        my $m = $self->{mSSMap}->{$slot}->{$ts};
        next if $mode ne DOM_INCLUDE_ALL && $m->servableLength() == 0;
        next if $mode eq DOM_ONLY_COMPLETE && !$m->isComplete();
        $model = $m;
        last;
    }
    return $model;
}

#Task2: Insert this here MFZModel $mdl in yo data structure
sub insertMFZModel {
    my __PACKAGE__ $self = shift || die;
    my $model = shift || die;

    my $ss = $model->{mSlotStamp};
    my $slot = SSSlot($ss);
    
    my $map = $self->{mSSMap}->{$slot};
    unless (defined $map) {
        $map = { };
        $self->{mSSMap}->{$slot} = $map;
    }
    my $ts = SSStamp($ss);
    my $omdl = $map->{$ts};
    if (defined($omdl)) {
        return SetError("Already inserted") if $model == $omdl;  # This exact thing already inserted
        my $len = $model->servableLength();
        my $olen = $omdl->servableLength();
        return SetError("Already have a better one")
            if $olen > $len || (($len == $olen) && oneIn(2));
        DPSTD("Replacing $omdl with $model");
    }
    $map->{$ts} = $model;
    return $model;
}

sub takeDeletedMap {
    my __PACKAGE__ $self = shift || die;
    my DeletedMap $dmap = shift || die;
    DPSTD($self->getTag().
          (defined($self->{mDeletedMap}) ? " Replacing " : " Initializing ").
          "deleted map");
    $self->{mDeletedMap} = $dmap;
}

# return undef and set $@ if problem, else return 1 if ss is deleted, and 0 if not
sub isDeletedSS {
    my __PACKAGE__ $self = shift || die;
    my $ss = shift || die;
    my $dmap = $self->{mDeletedMap};
    return DPSTD("No deleted map") unless defined($dmap);
    my ($slot,$stamp) = (SSSlot($ss), SSStamp($ss));
    my ($dflags,$dstamp) = ($dmap->slotFlags($slot), $dmap->slotStamp($slot));
    return DPSTD("dmap invalid") unless $dflags&DELETED_FLAG_SLOT_VALID;
    return 1 if ($dflags&DELETED_FLAG_SLOT_DELETED) && $dstamp >= $stamp;
    return 0;
}

#Task3: Reap any slotnum $sn MFZModels that are dominated by other
#       completed slotnum models, or are explicitly deleted
sub deleteDominatedInSlot {
    my __PACKAGE__ $self = shift || die;
    my $slot = shift || die;
    my $dom = undef;
    my $count = 0;
    my @tss = sort { $b <=> $a } keys %{$self->{mSSMap}->{$slot}};
    for my $ts (@tss) {
        my $m = $self->{mSSMap}->{$slot}->{$ts};
        if (defined($dom) || $self->isDeletedSS($m->{mSlotStamp})) {
            ++$count;
            if (defined($dom)) {
                DPSTD($dom->getTag()." dominates ".$m->getTag());
            } else {
                DPSTD($m->getTag()." is marked deleted");
            }
            delete $self->{mSSMap}->{$slot}->{$ts}; # This is all we have to do??
            $m->deleteMFZ();
        } elsif ($m->isComplete()) {
            $dom = $m; # Begin flushing from here
        }
    }
    return $count;
}

# Task4: Garbage-collect $models
sub garbageCollect {
    my __PACKAGE__ $self = shift || die;
    my $count = 0;
    for my $slot (keys %{$self->{mSSMap}}) {
        my $kilt = $self->deleteDominatedInSlot($slot);
        $count += $kilt if $kilt > 0;
    }
    return $count;
}

# Task5: Find or create the MFZModel for this $ss
sub getMFZModelForSS {
    my __PACKAGE__ $self = shift || die;
    my $ss = shift || die;
    my $model = $self->getMFZModelForSSIfAny($ss);
    unless (defined($model)) {
        $model = MFZModel->new($self->{mCDM}, $ss, SUBDIR_COMMON);
        $self->insertMFZModel($model);
    }
    return $model;
}

# Task6: Update MFZModel availability based on this $fpkt
sub updateMFZModelAvailability {
    my __PACKAGE__ $self = shift || die;
    my PacketCDM_F $fpkt = shift || die;
    my $ss = $fpkt->{mSlotStamp};
    my ($slot,$stamp) = (SSSlot($ss), SSStamp($ss));

    my $domby = undef;
    if ($self->isDeletedSS($ss)) {
        $domby = $self->getDominantMFZModelForSlot(DELETED_SLOT_NUMBER, DOM_ONLY_COMPLETE);
    } else {
        # Check if we already know this $fpkt's content is obsolete
        my $dom = $self->getDominantMFZModelForSlot($slot,DOM_ONLY_MAPPED);
        if (defined($dom)) {
            my $domstamp = SSStamp($dom->{mSlotStamp});
            if ($domstamp > $stamp) {
                $domby = $dom;
            }
        }
    }

    if (defined($domby)) {
        my $domss = $domby->{mSlotStamp};
        # They're obsolete.  Let's spread the good news about $domby
        DPSTD("Replying with ".SSToTag($domss)." to ".$fpkt->summarize()." about ".SSToTag($ss));
        my $cdm = $self->{mCDM} || die;
        my $fpkt2 = PacketCDM_F->makeFromMFZModel($domby) || die;
        $fpkt2->setDir8($fpkt->getDir8());
        my $pio = $cdm->getPIO() || die;
        $fpkt2->sendVia($pio);
        return;
    }

    # Theirs at least ties ours for dominance.  Record it.
    my $model = $self->getMFZModelForSS($ss); # Creating if need be
    $model->updateServableLength($fpkt->getDir8(), $fpkt->{mAvailableLength});
}

sub makeDirPath {
    my __PACKAGE__ $self = shift || die;
    my $indir = $self->{mInDir};
    my $cdm = $self->{mCDM};
    my $basedir = $cdm->getBaseDirectory();
    my $path = "$basedir/$indir";
    return $path;
}

sub getBaseDirectory {
    my __PACKAGE__ $self = shift || die;
    return $self->{mInDir};
}

sub checkFile {
    my __PACKAGE__ $self = shift || die;
    my $fn = shift || die;
    my $cdm = $self->{mCDM};
    my $model = MFZModel->tryLoad($cdm,$self->{mInDir},$fn);
    if (!defined($model)) {
        DPSTD($@);
        return undef;
    }
    return $self->insertMFZModel($model);
}

##VIRTUAL
sub init() {
    my __PACKAGE__ $self = shift or die;
    DPPushPrefix($self->getTag());
    $self->loadDirectory();
    DPPopPrefix();
}

sub loadFiles {
    my __PACKAGE__ $self = shift || die;
    my $dirpath = $self->makeDirPath();
    opendir my $fh, $dirpath or return SetError("Can't read $dirpath: $!");
    my @files = sort { SScmpSS(SSFromPath($b),SSFromPath($a)) } grep { SSFromPath($_) } readdir $fh;
    closedir $fh or die $!;
    DPSTD("${\FUNCNAME} FILES ".join(", ",@files));
    return @files;
}

sub loadDirectory {
    my __PACKAGE__ $self = shift || die;
    my @files = $self->loadFiles();
    # Just process them all atomically for now, until we actually have
    # a clue about updating incrementally.
    for my $file (@files) {
        $self->checkFile($file); 
    }
}

# Report on all incomplete MFZModels
sub reportMFZStats {
    my __PACKAGE__ $self = shift;
    my @slots = sort keys %{$self->{mSSMap}};    
    my $maxlen = 16;
    my @ret = ();
    for my $slot (@slots) {
        my @tss = sort { $b <=> $a } keys %{$self->{mSSMap}->{$slot}};
        for my $ts (@tss) {
            my $ss = SSMake($slot,$ts);
            my $sstag = SSToTag($ss);
            my $m = $self->{mSSMap}->{$slot}->{$ts};
            unless ($m->isComplete()) {
                my $len = $m->pendingLength();
                my $totlen = $m->totalLength() || 0;  # Undef if no map yet
                my $label = $m->getLabelIfAvailable();
                $label ||= "--";
                push @ret,
                    sprintf(" %4s %4s %9s %*s\n",
                            $totlen > 0 ? formatPercent(100.0*$len/$totlen) : "-- ",
                            formatSize($len),
                            $sstag,
                            -$maxlen, $label);
            }
        }
    }
    return @ret;
}

## Methods
sub new {
    my ($class,$cdm, $dir) = @_;
    defined $dir or die;
    my $self = fields::new($class);
    $self->SUPER::new("CM:$dir",$cdm);

    $self->{mInDir} = $dir;   
    $self->{mInDirModTime} = undef;
    $self->{mSSMap} = { };          # { slotnum -> { ts -> MFZModel } }
    $self->{mDeletedMap} = undef;   # instance of DeletedMap

    $self->{mCDM}->getTQ()->schedule($self);
    $self->defaultInterval(-20); # Run about every 10 seconds if nothing happening

    return $self;
}

# return undef unless a fpkt was sent
sub maybeAnnounceSomething {
    my __PACKAGE__ $self = shift || die;

    my $model = $self->pickUndominatedMFZModel();
    return undef unless defined $model;

    my $cdm = $self->{mCDM} || die;
    my $hoodm = $cdm->{mNeighborhoodManager} || die;
    my $ngb = $hoodm->getRandomOpenNgbMgr();
    return undef unless defined $ngb;

    my $fpkt = PacketCDM_F->makeFromMFZModel($model) || die;
    $fpkt->setDir8($ngb->{mDir8});
    my $pio = $cdm->getPIO() || die;
    return $fpkt->sendVia($pio);
}

sub handleDataChunk {
    my __PACKAGE__ $self = shift || die;
    my PacketCDM_D $dpkt = shift || die;

    my $ss = $dpkt->{mSlotStamp};
    my $model = $self->getMFZModelForSSIfAny($ss);
    return DPSTD("No model for ".$dpkt->summarize()) unless defined $model;

    $model->receiveDataChunk($dpkt);
}

sub sendDataChunk {
    my __PACKAGE__ $self = shift || die;
    my PacketCDM_C $cpkt = shift || die;

    my $ss = $cpkt->{mSlotStamp};
    my $model = $self->getMFZModelForSSIfAny($ss);
    return DPSTD("No model for ".$cpkt->summarize()) unless defined $model;

    my $cdm = $self->{mCDM} || die;
    my $dpkt = $model->makeDPktFromCPkt($cpkt);
    return DPSTD("No reply to ".$cpkt->summarize()) unless defined $dpkt;

    my $pio = $cdm->getPIO() || die;
    return $dpkt->sendVia($pio);
}

sub requestChunkFrom {
    my __PACKAGE__ $self = shift || die;
    my $model = shift || die;
    my $cdm = $self->{mCDM} || die;
    my $cpkt = PacketCDM_C->makeFromMFZModel($model) || die;

    my $pio = $cdm->getPIO() || die;
    return $cpkt->sendVia($pio);
}

# return undef unless a cpkt was sent
sub maybeRequestSomething {
    my __PACKAGE__ $self = shift || die;
    my $model = $self->pickImprovableMFZModel();
    return undef unless defined $model;
    return $self->requestChunkFrom($model);
}

sub reloadCommon {
    my __PACKAGE__ $self = shift || die;
    my @files = $self->loadFiles();
    my $cdm = $self->{mCDM};

    for my $fn (@files) {
        my $ss = SSFromPath($fn) or next;
        my $model = $self->getMFZModelForSSIfAny($ss);
        next if defined $model;
        DPSTD("Trying to load new file $fn");
        $model = MFZModel->tryLoad($cdm,$self->{mInDir},$fn);
        if (defined $model) {
            DPSTD("Loaded $fn");
            $self->insertMFZModel($model);
        } else {
            DPSTD("Load failed: $@");
        }
    }
}

sub maybeReloadCommon {
    my __PACKAGE__ $self = shift || die;
    my $path = $self->makeDirPath();
    my $modtime = (stat($path))[9];
    my $prevmod = $self->{mInDirModTime};
    unless (defined($prevmod) && $modtime <= $prevmod) {
        $self->reloadCommon();
        $self->{mInDirModTime} = $modtime;
    }
}    

sub update {
    my __PACKAGE__ $self = shift || die;
    $self->maybeReloadCommon();
    $self->maybeAnnounceSomething();
    $self->maybeRequestSomething();
    $self->garbageCollect();
}

sub onTimeout {
    my __PACKAGE__ $self = shift || die;
    DPPushPrefix($self->getTag());
    $self->update();
    DPPopPrefix(); 
}

1;
