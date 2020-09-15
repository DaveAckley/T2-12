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
    mNeighborFPacket
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
    DPSTD("Trying to load $path");

    my $pathbak = "$path.bak";
    rename $path,$pathbak or die $!;
    open my $fh, "<", $pathbak or die $!;
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

    DPSTD($model->getTag()." created");
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

    {
        my $disklen = $self->servableLength();
        my $appendat = $disklen + length($self->{mBufferedData});
        return $appendat if $at != $appendat;
    }

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

sub deleteMFZ {
    my __PACKAGE__ $self = shift || die;
    die "XXX IMmPLEMNTDNME";
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

## Methods
sub new {
    my ($class,$cdm,$ss, $dir) = @_;
    defined $ss or die;
    defined $dir or die;
    my $self = fields::new($class);
    $self->SUPER::new(SSToFileName($ss),$cdm);

    $self->{mInDir} = $dir;       # Unused til length reaches 1KB
    $self->{mSlotStamp} = $ss;    # Untrusted til length reaches 1KB
    $self->{mFileHandle} = undef; # Nonexistent til length reaches 1KB
    $self->{mCDMap} = undef;      # Unknown til length reaches 1KB
    $self->{mBufferedData} = "";  # Nothing buffered to start

    $self->{mXsumDigester} = undef;
    $self->{mNeighborFPacket} = undef; # Nonexistent til someone announces to us

    $self->{mCDM}->getTQ()->schedule($self);
    $self->defaultInterval(-20); # Run about every 10 seconds if nothing happening

    return $self;
}

sub update {
    my __PACKAGE__ $self = shift || die;
    
}

sub onTimeout {
    my __PACKAGE__ $self = shift || die;
    DPPushPrefix($self->getTag());
    $self->update();
    DPPopPrefix(); 
}


1;
