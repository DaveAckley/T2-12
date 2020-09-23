## Module stuff
package MFZModel;
use strict;
use base 'TimeoutAble';
use fields qw(
    mSlotStamp
    mInDir
    mFileHandle
    mBufferedData
    mCDMap
    mXsumDigester
    mSources
    mLastPositionRequested
    mLastActivityTime
    mInboundChunks
    mCreationTime
    mCreationLength
    mCompletionTime
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
use PacketCDM_C;
use PacketCDM_D;
use SlotConfig;

## CLASS METHOD
# MFZModel::tryLoad($cdm,$dir,$file) returns MFZModel or undef and sets $@
sub tryLoad {
    my $class = shift or die;
    my $cdm = shift or die;
    my $dir = shift or die;
    my $file = shift or die;
    my $ss = SSFromPath($file);
    die unless defined $ss;
    my $model = MFZModel->new($cdm,$ss,$dir);

    my $path = $model->makePath();
    #DPSTD("Trying to load $path");

    my $pathbak = "$path.bak";
    rename $path,$pathbak or die $!;
    open my $fh, "<", $pathbak or die $!;
    $model->{mCreationLength} = -s $fh;
    my $len;
    my $data;
    my $pos = 0;
    while (($len = read($fh,$data,600)) > 0) {
        my $ret = $model->addChunkAt($data,$pos);
        last if $ret == 0;
        if ($ret < 0) {
            close $fh or die $!;
            my $pathbad = "$path.bad";
            rename $pathbak,$pathbad or die $!;
            return SetError("Renamed to $pathbad: $@");
        }
        $pos = $ret;
    }
    close $fh or die $!;
    unlink $pathbak;

    $model->noteComplete();
    return $model;
}

sub getLabelIfAvailable {
    my __PACKAGE__ $self = shift || die;
    return $self->{mCDMap}->{mLabel} if defined($self->{mCDMap});
    return undef;
}

# Return 
sub dominates {
    my __PACKAGE__ $self = shift || die;
    my __PACKAGE__ $other = shift || die;
    die "XXXX KILL ME I DONT EXIST";
}

sub makePath {
    my __PACKAGE__ $self = shift || die;
    my $indir = $self->{mInDir};
    my $cdm = $self->{mCDM};
    my $basedir = $cdm->getBaseDirectory();
    my $ss = $self->{mSlotStamp} || die;
    my $fn = SSToFileName($ss);
    my $path = "$basedir/$indir/$fn";
    return $path;
}

## return 0 if complete,
#  return next position > 0 if chunk added or in wrong position,
#  return -1 and set $@ if validation failed somehow
sub addChunkAt {
    my __PACKAGE__ $self = shift || die;
    my $chunk = shift; die unless defined $chunk;
    my $at = shift; die unless defined $at;

    my $appendat = $self->pendingLength();
    return $appendat if $at != $appendat;

    my $chunklen = length($chunk);

    ## (Q1) Are we in the CDM10 header?
    if ($at < CDM10_FULL_MAP_LENGTH) {  # (A1) Yes
        ## (Q1.1) Does chunk at least finish the header?
        if ($at + $chunklen < CDM10_FULL_MAP_LENGTH) {

            # (A1.1) No.  Just accumulate
            $self->{mBufferedData} .= $chunk;
            return length($self->{mBufferedData});
        }

        # (A1.1) Yes. Chew off rest of map and process.
        my $takelen = CDM10_FULL_MAP_LENGTH - $at;
        $self->{mBufferedData} .= substr($chunk,0,$takelen);
        substr($chunk,0,$takelen) = "";
        $at += $takelen;
        $chunklen -= $takelen;

        my $cdmap = Packable::parse($self->{mBufferedData});
        return SetError("Malformed CDM10 map",-1) unless $cdmap->isa('CDMap');
        return SetError("Invalid signature: $@",-1) unless $cdmap->verifySignature();
        $self->{mCDMap} = $cdmap;

        # Check the map against our original SS
        return SetError(sprintf("Expected %s, got %s",
                                SSToFileName($self->{mSlotStamp}),
                                SSToFileName($cdmap->{mSlotStamp})),-1)
            unless $self->{mSlotStamp} == $cdmap->{mSlotStamp};

        my $path = $self->makePath();
        open $self->{mFileHandle}, '+>', $path
            or return SetError("Can't create $path:$!",-1);
        $self->{mFileHandle}->autoflush(1);

        # Advance the file on disk.
        print {$self->{mFileHandle}} $self->{mBufferedData};
        $self->{mBufferedData} = "";

        # Set up to digest rest of the file
        $self->{mXsumDigester} = Digest::SHA->new(512);
    }
    
    return -s $self->{mFileHandle} if $chunklen == 0;

    my $cdmap = $self->{mCDMap};
    my $mappedlen = $cdmap->{mMappedFileLength};
    my $totallen = $mappedlen + CDM10_FULL_MAP_LENGTH;

    ## (Q2) Is chunk enough to finish the whole file?
    if ($at + $chunklen >= $totallen) {  # (A2)
        return -1 if $at + $chunklen != $totallen;  # Hit it on the nose please

        $self->{mXsumDigester}->add($self->{mBufferedData});
        $self->{mXsumDigester}->add($chunk);
        my $finalxsum = $self->{mXsumDigester}->digest();

        return SetError("Final checksum mismatch",-1)
            unless $finalxsum eq $cdmap->{mMappedFileChecksum};

        # Advance the file to its end
        seek($self->{mFileHandle},0,2)   # Seek to eof
            or die "Why does seek die? $!";
        print {$self->{mFileHandle}} $self->{mBufferedData};
        print {$self->{mFileHandle}} $chunk;
        $self->{mBufferedData} = "";

        ## Reopen file as read-only?
        return 0;  ## SUCCESS
    }

    ## (Q3) Is chunk enough to finish another block?
    my $blocksize = 1<<$cdmap->{mBlockSizeBits};
    while (length($self->{mBufferedData}) + $chunklen >= $blocksize) { # (A3) Yes
        # Be at a block boundary on disk
        die unless (((-s $self->{mFileHandle}) - CDM10_FULL_MAP_LENGTH) % $blocksize) == 0;

        # What block are we in?
        my $block = int(($at - CDM10_FULL_MAP_LENGTH)/$blocksize);

        # Take what we need to finish the block
        my $takelen = $blocksize - length($self->{mBufferedData});
        $self->{mBufferedData} .= substr($chunk,0,$takelen);
        substr($chunk,0,$takelen) = "";
        $at += $takelen;
        $chunklen -= $takelen;

        # Save the digester in case things go sideways
        my $preblockdigester = $self->{mXsumDigester}->clone();

        # Feed the digester
        $self->{mXsumDigester}->add($self->{mBufferedData});
        my $ixsum = $self->{mXsumDigester}->clone()->digest();
        my $xsum8 = substr($ixsum,0,8);

        # Check the split xsum

        ## If we have a bad checksum here, it's not enough to just
        ## reject the chunk.  We also need to dump the buffered data
        ## (and reset the digester) to get back to the last known good
        ## position, and then tell caller to restart from there.
        unless ($cdmap->{mIncrementalXsums}->[$block] eq $xsum8) {
            DPSTD("Bad checksum, restarting block $block");
            $self->{mBufferedData} = "";
            $self->{mXsumDigester} = $preblockdigester;
            return -s $self->{mFileHandle};
        }

        # Advance the disk by a block
        seek($self->{mFileHandle},0,2)   # Seek to eof
            or die "Why does seek die? $!";
        print {$self->{mFileHandle}} $self->{mBufferedData};
        $self->{mBufferedData} = "";
    }

    ## Mop up any leftover
    $self->{mBufferedData} .= $chunk;
    return (-s $self->{mFileHandle}) + length($self->{mBufferedData});
}

sub isComplete {
    my __PACKAGE__ $self = shift || die;
    my $slen = $self->servableLength();
    return undef unless $slen > 0;
    return $slen == $self->totalLength();
}

sub totalLength {
    my __PACKAGE__ $self = shift || die;
    return undef unless defined $self->{mCDMap}; # Might be too soon to know
    return $self->{mCDMap}->{mMappedFileLength} + CDM10_FULL_MAP_LENGTH;
}
    
# servableLength + bufferedData
sub pendingLength {
    my __PACKAGE__ $self = shift || die;
    return $self->servableLength() + length($self->{mBufferedData});
}

sub servableLength {
    my __PACKAGE__ $self = shift || die;
    return 0 unless defined $self->{mFileHandle};
    return -s $self->{mFileHandle};
}

# NOTE: CALLER must clean up ContentManager
sub deleteMFZ {
    my __PACKAGE__ $self = shift || die;
    
    # Eliminate the file, if it exists
    if ($self->servableLength() > 0) {
        my $path = $self->makePath();
        my $pathDominated = $path."~";
        rename $path, $pathDominated or die "Can't rename '%path': $!";
        DPSTD($self->getTag()." renamed to $pathDominated");
    }

    # Eliminate the model
    $self->unschedule();
}

sub readChunk {
    my __PACKAGE__ $self = shift || die;
    my $index = shift; die unless defined $index;
    my $amount = shift; die unless defined $amount;
    my $fh = $self->{mFileHandle} || die;

    my $data;
    seek($fh,$index,0) or die "When does seek die?  Now: $!";
    my $len = read($fh,$data,$amount);
    return undef unless $len == $amount;

    return $data;
}
    
sub makeDPktFromCPkt {
    my __PACKAGE__ $self = shift || die;
    my PacketCDM_C $cpkt = shift || die;
    my $index = $cpkt->{mFilePosition};
    my $max = $self->servableLength();
    return undef if $max <= $index;  # Got nothing for you
    my $avail = $max - $index;
    my $sendlen = max(0,min($avail, MAX_D_TYPE_DATA_LENGTH));
    my $data = $self->readChunk($index,$sendlen);
    return undef unless defined $data;
    
    my $dpkt = PacketCDM_D::makeFromCPktAndData($cpkt,$data);
    return $dpkt;
}

use constant MFZMODEL_TIMEOUT_FREQUENCY => 3;
use constant MFZMODEL_MAX_WAIT_FOR_ACTIVITY => 5;

## Methods
sub new {
    my ($class,$cdm,$ss, $dir) = @_;
    defined $ss or die;
    defined $dir or die;
    my $self = fields::new($class);
    $self->SUPER::new(SSToFileName($ss),$cdm);
    DPSTD($self->getTag()." record created");
    $self->{mCreationTime} = now();
    $self->{mCreationLength} = 0; # Updated if tryLoad runs on this
    $self->{mCompletionTime} = undef;

    $self->{mInDir} = $dir;       # Unused til length reaches 1KB
    $self->{mSlotStamp} = $ss;    # Untrusted til length reaches 1KB
    $self->{mFileHandle} = undef; # Nonexistent til length reaches 1KB
    $self->{mCDMap} = undef;      # Unknown til length reaches 1KB
    $self->{mBufferedData} = "";  # Nothing buffered to start

    $self->{mXsumDigester} = undef;
    $self->{mSources} = { };      # { d8 -> [ servableLength activityTime ] }
    $self->{mLastPositionRequested} = -1; # The END position of the farthest chunk we've requested
    $self->{mLastActivityTime} = now() - MFZMODEL_TIMEOUT_FREQUENCY; # Set to go
    $self->{mInboundChunks} = [];  # None
    
    $self->defaultInterval(-2*MFZMODEL_TIMEOUT_FREQUENCY); # Run about every 3 seconds
    $self->{mCDM}->getTQ()->schedule($self);

    return $self;
}

sub selectServableD8 { # Return undef or a d8 that has stuff we could request
    my __PACKAGE__ $self = shift || die;
    return undef if $self->isComplete();
    
    my $pick8 = undef;
    my $weight = 0;
    my $frontier = $self->{mLastPositionRequested};
    for my $d8 (keys %{$self->{mSources}}) {
        my ($servablelen, $activitytime) = @{$self->{mSources}->{$d8}};
        next unless $servablelen > $frontier;   # Skip if they can't give us what we need
        next unless now() - $activitytime < SERVER_VIABILITY_SECONDS; # Or if they're ghosting us
        $pick8 = $d8 if oneIn(++$weight);       # Else pick uniformly
    }
    return $pick8;
}

sub getD8Rec {
    my __PACKAGE__ $self = shift || die;
    my $d8 = shift; defined($d8) or die;
    my $rec = $self->{mSources}->{$d8};
    unless (defined($rec)) {
        $rec = [ -1, now() ];  # Default record offers nothing but is active
        $self->{mSources}->{$d8} = $rec;
    }
    return $rec;
}

sub updateServableLength { # record that $d8 offers $length and mark active
    my __PACKAGE__ $self = shift || die;
    my $d8 = shift;        defined($d8) || die;
    my $length = shift;    defined($length) || die;
    my $rec = $self->getD8Rec($d8);

    $rec->[0] = $length;
    $rec->[1] = now();
}

sub markActiveD8 { # record that $d8 is active
    my __PACKAGE__ $self = shift || die;
    my $d8 = shift;        defined($d8) || die;
    my $rec = $self->getD8Rec($d8);

    $rec->[1] = now();
}
    
sub resetTransfer {
    my __PACKAGE__ $self = shift || die;
    DPSTD($self->getTag()." reset transfer");
    $self->{mInboundChunks} = [];   # Dump any unlanded dpkts
    $self->{mLastPositionRequested} = $self->pendingLength();
    $self->markActive();
}

sub advance {
    my __PACKAGE__ $self = shift || die;
    $self->landInboundChunks();
    $self->maybeSendNewRequests();
}

sub receiveDataChunk {
    my __PACKAGE__ $self = shift || die;
    my PacketCDM_D $dpkt = shift || die;
    push @{$self->{mInboundChunks}}, $dpkt;
    $self->advance();
}

sub noteComplete {
    my __PACKAGE__ $self = shift || die;
    $self->{mCompletionTime} ||= now();
    my $secs = $self->{mCompletionTime} - $self->{mCreationTime};
    $secs = 1 if $secs == 0;

    my $totlen = $self->totalLength();   
    my $uselen = ($self->{mCreationLength} == $totlen) ?
        $totlen : $totlen - $self->{mCreationLength};

    my $bytespersec = $uselen / $secs;
    DPSTD(sprintf("%s complete. %sB %s in %s, %sBPS",
                  $self->getTag(),
                  formatSize($uselen,1),
                  (($uselen == $totlen) ? "loaded" :
                   "(of ".formatSize($totlen,1).")"),
                  formatSeconds($secs,1),
                  formatSize($bytespersec,1)));
    SlotConfig::configureMFZModel($self);
}

sub landInboundChunks {
    my __PACKAGE__ $self = shift || die;
    my @stillInFlight;
    while (my $dpkt = shift @{$self->{mInboundChunks}}) {
        if ($self->isComplete()) {
            DPSTD("We are complete.  Ignoring ".$dpkt->summarize());
            next;
        }
        my $currentFilePos = $self->pendingLength();
        if ($dpkt->{mFilePosition} == $currentFilePos) {
            my $ret = $self->addChunkAt($dpkt->{mData},$dpkt->{mFilePosition});
            die "$@" if $ret < 0;
            $self->markActive();
            $self->noteComplete() if $ret == 0;
        } elsif ($dpkt->{mFilePosition} > $currentFilePos &&
                 $dpkt->{mFilePosition} <= $self->{mLastPositionRequested}) {
            push @stillInFlight, $dpkt;
        } else {  # obsolete or beyond what we requested
            DPSTD(sprintf("Ignoring data %+d bytes from %d",
                          ($dpkt->{mFilePosition} -  $currentFilePos),
                          $currentFilePos));
            next;
        }
        $self->markActiveD8($dpkt->getDir8());
    }
    $self->{mInboundChunks} = \@stillInFlight; # Keep circling the airport
}

sub chunkSizeAtFP {
    my __PACKAGE__ $self = shift || die;
    my $fromFilePosition = shift; defined $fromFilePosition or die;
    my $totalLength = $self->totalLength();
    return MAX_D_TYPE_DATA_LENGTH  # It's a full packet if 
        unless (defined $totalLength); # we don't have the map yet it
    return MAX_D_TYPE_DATA_LENGTH  # It's a full packet if 
        if $fromFilePosition + MAX_D_TYPE_DATA_LENGTH <= $totalLength; # there's room for it
    return $totalLength - $fromFilePosition;
}

sub maybeSendNewRequests {
    my __PACKAGE__ $self = shift || die;
    return if $self->isComplete();  # Ah no
    
    my $pio = $self->{mCDM}->getPIO() || die;
    my $currentFilePos = $self->pendingLength();
    while (1) {
        my $inflight = $self->{mLastPositionRequested} - $currentFilePos;
        last if $inflight >= MAX_MFZ_DATA_IN_FLIGHT;  # Too much pending already

        my $nextchunksize = $self->chunkSizeAtFP($self->{mLastPositionRequested});
        last if $nextchunksize == 0;                  # Already seeing EOF coming

        my $d8 = $self->selectServableD8();
        last unless defined $d8;                      # Nobody's got what we need
        
        my $cpkt = PacketCDM_C->new();
        $cpkt->setDir8($d8);
        $cpkt->{mSlotStamp} = $self->{mSlotStamp};
        $cpkt->{mFilePosition} = $self->{mLastPositionRequested};

        if ($cpkt->sendVia($pio)) {
            $self->{mLastPositionRequested} += $nextchunksize;
        } else {
            last;  # Can't ship now??
        }
    }
}

sub markActive {
    my __PACKAGE__ $self = shift || die;
    $self->{mLastActivityTime} = now();
}

sub update {
    my __PACKAGE__ $self = shift || die;
    return if $self->isComplete();

    if (aged($self->{mLastActivityTime},MFZMODEL_MAX_WAIT_FOR_ACTIVITY)) {
        $self->resetTransfer();
        $self->advance();
        return;
    }
}

sub onTimeout {
    my __PACKAGE__ $self = shift || die;
    DPPushPrefix($self->getTag());
    $self->update();
    DPPopPrefix(); 
}


1;
