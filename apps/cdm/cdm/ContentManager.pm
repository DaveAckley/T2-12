## Module stuff
package ContentManager;
use strict;
use base 'TimeoutAble';
use fields qw(
    mInDir
    mSSMap
    mFilesToCheck
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

sub pickImprovableMFZModel {
    my __PACKAGE__ $self = shift || die;
    my $slot = pickOne(keys %{$self->{mSSMap}});
    return undef unless defined $slot;
    my $model = undef;
    my @tss = sort {$a <=> $b} keys %{$self->{mSSMap}->{$slot}};
    for my $ts (@tss) {
        my $m = $self->{mSSMap}->{$slot}->{$ts};

        next if $m->isComplete();

        my $fpkt = $m->{mNeighborFPacket};
        next unless defined $fpkt;
        next unless $fpkt->{mAvailableLength} > $m->pendingLength();
        
        $model = $m;
        last;
    }
    return $model;
}

# Task1: Pick a random undominated MFZModel to announce or perhaps grow
sub pickUndominatedMFZModel {
    my __PACKAGE__ $self = shift || die;
    my $slot = pickOne(keys %{$self->{mSSMap}});
    return undef unless defined $slot;
    my $model = undef;
    my @tss = sort {$a <=> $b} keys %{$self->{mSSMap}->{$slot}};
    for my $ts (@tss) {
        my $m = $self->{mSSMap}->{$slot}->{$ts};
        next if $m->servableLength() == 0;
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

#Task3: Reap any slotnum $sn MFZModels that are dominated by other
#       completed slotnum models
sub deleteDominatedInSlot {
    my __PACKAGE__ $self = shift || die;
    my $slot = shift || die;
    my $count = -1;
    my @tss = sort { $a <=> $b } keys %{$self->{mSSMap}->{$slot}};
    for my $ts (@tss) {
        my $m = $self->{mSSMap}->{$slot}->{$ts};
        if ($count >= 0) {
            ++$count;
            $m->deleteMFZ();
            delete $self->{mSSMap}->{$slot}->{$ts};
        } elsif ($m->isComplete()) {
            $count = 0; # Begin flushing from here
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
    my $model = $self->getMFZModelForSS($ss); # Creating if need be
    my $ngbf = $model->{mNeighborFPacket};
    $model->{mNeighborFPacket} = $fpkt     # Take this f packet
        if !defined($ngbf)                 # ..if it's the first one
        || ($ngbf->{mAvailableLength} < $fpkt->{mAvailableLength})  # ..or it offers more
        || ($fpkt->{mAvailableLength} > $model->servableLength() && oneIn(4));  # ..or it offers something, and 25%
    return $model->{mNeighborFPacket};
}


sub makeDirPath {
    my __PACKAGE__ $self = shift || die;
    my $indir = $self->{mInDir};
    my $cdm = $self->{mCDM};
    my $basedir = $cdm->getBaseDirectory();
    my $path = "$basedir/$indir";
    return $path;
}

# sub checkNextFile {
#     my __PACKAGE__ $self = shift || die;
#     return undef unless my $fn = shift @{$self->{mFilesToCheck}};
#     return $self->checkFile($fn);
# }

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

sub loadDirectory {
    my __PACKAGE__ $self = shift || die;
    my $dirpath = $self->makeDirPath();
    opendir my $fh, $dirpath or return SetError("Can't read $dirpath: $!");
    my @files = grep { SSFromPath($_) } readdir $fh;
    closedir $fh or die $!;
    # Just do it all atomically for now, until we actually have a clue
    # about updating incrementally.
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
        my @tss = sort { $a <=> $b } keys %{$self->{mSSMap}->{$slot}};
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
    $self->{mSSMap} = { };        # { slotnum -> { ts -> MFZModel } }
    $self->{mFilesToCheck} = [ ]; # unsorted filenams from readdir

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

    my $fpkt = PacketCDM_F->makeFromMFZModel($model);
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

    my $index = $dpkt->{mFilePosition};
    my $data = $dpkt->{mData};
    my $ret = $model->addChunkAt($data,$index);

    return DPSTD("Rejected chunk ".$dpkt->summarize()) unless $ret >= 0;

    if (!$model->isComplete()) {
        $self->requestChunkFrom($model);
    }
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
    my $cpkt = PacketCDM_C->makeFromMFZModel($model);

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

sub update {
    my __PACKAGE__ $self = shift || die;
    $self->maybeAnnounceSomething();
    $self->maybeRequestSomething();
}

sub onTimeout {
    my __PACKAGE__ $self = shift || die;
    DPPushPrefix($self->getTag());
    $self->update();
    DPPopPrefix(); 
}

1;
