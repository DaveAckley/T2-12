## Module stuff
package StatusReporter;
use strict;
use base 'TimeoutAble';
use fields qw(
    mInitTime
    mLastSampleTime
    mRatesDir8
    );

use Exporter qw(import);

our @EXPORT_OK = qw();
our %EXPORT_TAGS;

## Imports
use List::Util qw(shuffle);

use DP qw(:all);
use Constants qw(:all);
use T2Utils qw(:all);

use constant REC_DIR8 => 0;
use constant REC_TOTIN => REC_DIR8+1;
use constant REC_TOTOUT => REC_TOTIN+1;
use constant REC_FASTIN => REC_TOTOUT+1;
use constant REC_FASTOUT => REC_FASTIN+1;
use constant REC_MEDIN => REC_FASTOUT+1;
use constant REC_MEDOUT => REC_MEDIN+1;
use constant REC_SLOWIN => REC_MEDOUT+1;
use constant REC_SLOWOUT => REC_SLOWIN+1;
use constant REC_COUNT => REC_SLOWOUT+1;

use constant FAST_FRAC_OLD => 0.9200;  # time constant  ~1min (on 5sec sampling)
use constant MED_FRAC_OLD  => 0.9917;  # time constant ~10min 
use constant SLOW_FRAC_OLD => 0.9986;  # time constant ~60min

use constant FAST_FRAC_NEW => 1-FAST_FRAC_OLD;
use constant MED_FRAC_NEW => 1-MED_FRAC_OLD;
use constant SLOW_FRAC_NEW => 1-SLOW_FRAC_OLD;

## Methods
sub new {
    my StatusReporter $self = shift;
    my $cdm = shift;
    defined $cdm or die;
    unless (ref $self) {
        $self = fields::new($self); # really a class
    }

    $self->SUPER::new("StatRep",$cdm);

    $self->{mInitTime} = now(); 
    $self->{mLastSampleTime} = undef; 
    $self->{mRatesDir8} = { }; #  { dir8 -> [dir8 totin totout fastin fastout slowin slowout] }

    $self->{mCDM}->getTQ()->schedule($self);
    $self->defaultInterval(5); # Run every 5 seconds modulo jitter

    return $self;
}

sub captureBulkIOStats {
    my __PACKAGE__ $self = shift or die;
    my $now = now();
    my $diffsec = 1;
    $diffsec = $now - $self->{mLastSampleTime} if defined $self->{mLastSampleTime};
    $self->{mLastSampleTime} = $now;

    open HDL, "<",  PATH_DATA_IOSTATS or die "Can't open ${\PATH_DATA_IOSTATS}: $!";
    while (<HDL>) {
        my ($dir8, $psan, $sfan, $toan, $mfmbsent, $mfmbrcvd, $mfmpsent, $mfmprcvd, $svcbsent, $svcbrcvd, $svcpsent, $svcprcvd)
            = split(" ");
        next unless $dir8 =~ /(\d+)/;
#        DPSTD("($dir8, $psan, $sfan, $toan, $mfmbsent, $mfmbrcvd, $mfmpsent, $mfmprcvd, $svcbsent, $svcbrcvd, $svcpsent, $svcprcvd)");
        my $rec = $self->{mRatesDir8}->{$dir8};
        if (!defined($rec)) {
            $rec = [$dir8, $svcbrcvd, $svcbsent, undef, undef, undef, undef];
            $self->{mRatesDir8}->{$dir8} = $rec;
        } else {
            my $diffin = $svcbrcvd - $rec->[REC_TOTIN];
            my $diffout = $svcbsent - $rec->[REC_TOTOUT];
            $rec->[REC_TOTIN] = $svcbrcvd;
            $rec->[REC_TOTOUT] = $svcbsent;
            if ($diffsec > 0) {
                my $insample = $diffin / $diffsec;
                my $outsample = $diffout / $diffsec;
                $rec->[REC_FASTIN] =
                    defined($rec->[REC_FASTIN]) ? FAST_FRAC_OLD * $rec->[REC_FASTIN] + FAST_FRAC_NEW * $insample : $insample;
                $rec->[REC_MEDIN] =
                    defined($rec->[REC_MEDIN])  ? MED_FRAC_OLD *  $rec->[REC_MEDIN]  + MED_FRAC_NEW * $insample : $insample;
                $rec->[REC_SLOWIN] =
                    defined($rec->[REC_SLOWIN]) ? SLOW_FRAC_OLD * $rec->[REC_SLOWIN] + SLOW_FRAC_NEW * $insample : $insample;
                $rec->[REC_FASTOUT] =
                    defined($rec->[REC_FASTOUT]) ? FAST_FRAC_OLD * $rec->[REC_FASTOUT] + FAST_FRAC_NEW * $outsample : $outsample;
                $rec->[REC_MEDOUT] =
                    defined($rec->[REC_MEDOUT])  ? MED_FRAC_OLD *  $rec->[REC_MEDOUT] + MED_FRAC_NEW * $outsample : $outsample;
                $rec->[REC_SLOWOUT] =
                    defined($rec->[REC_SLOWOUT]) ? SLOW_FRAC_OLD * $rec->[REC_SLOWOUT] + SLOW_FRAC_NEW * $outsample : $outsample;
            }
        }
    }
}

##VIRTUAL
sub init {
    my __PACKAGE__ $self = shift or die;
    $self->captureBulkIOStats();
    DPSTD(__PACKAGE__. " init called via ".$self->getTag());
}

sub checkForEth0Inet {
    my __PACKAGE__ $self = shift or die;
    my $cmd = "ifconfig eth0";
    my $output = `$cmd`;
    my $addr;
    $addr = "[$1]" if $output =~ /inet\s+([.0-9]+)\s+netmask/s;
    return $addr;
}

sub writeBulkIOStats {
    my __PACKAGE__ $self = shift or die;
    my $uptime = $self->{mLastSampleTime} - $self->{mInitTime};
    my $basedir = $self->{mCDM}->getBaseDirectory();
    my $hoodmgr = $self->{mCDM}->{mNeighborhoodManager} or die;
    my $path = ${\PATH_REPORT_IOSTATS};
    
    # Don't die if we can't write $path
    unless (open HDL, ">", $path) {
        print "writeBulkIOStats: Can't write $path: $!";
        return;
    }

    my $hdr = $self->checkForEth0Inet() || "CDM UPTIME"; # Tell us yo damn addr if you got one.
    print HDL $hdr." ".formatSeconds($uptime,1)."\n";

    my $cmgr = $self->{mCDM}->{mContentManager};
    my @progress = $cmgr->reportMFZStats();
    for my $mfz (@progress) {
        printf(HDL "%s",$mfz);
    }

    for my $dir6 (getDir6s()) {
        next unless $hoodmgr->ngbMgr($dir6)->state() == NGB_STATE_OPEN;
        my $dir8 = mapDir6ToDir8($dir6);
        my $rec = $self->{mRatesDir8}->{$dir8};
        my ($infast, $outfast) = ($rec->[REC_FASTIN], $rec->[REC_FASTOUT]);
        my ($inmed, $outmed)   = ($rec->[REC_MEDIN],  $rec->[REC_MEDOUT]);
        my ($inslow, $outslow) = ($rec->[REC_SLOWIN], $rec->[REC_SLOWOUT]);
        next if
            $infast==0 && $outfast==0 &&
            $inmed==0  && $outmed==0 &&
            $inslow==0 && $outslow==0;
        printf(HDL "%s %s %s/%s %s/%s %s\n",
               getDir8Name($dir8),
               formatSize($infast),
               formatSize($outfast),
               formatSize($inmed),
               formatSize($outmed),
               formatSize($inslow),
               formatSize($outslow)
            );
    }

    my $epm = $self->{mCDM}->{mEPManager} || die;
    my @epstatus = $epm->statusLines();
    my $count = 0;
    my $maxlines = 5;
    for my $line (@epstatus) {
        if (++$count >= $maxlines) {
            print HDL "..\n";
            last;
        }
        print HDL " $line\n";
    }
    # my $dmpipe =  $dirsmgr->getDMPipeline();
    # my @pipeline = $dmpipe->reportMFZStats();
    # for my $pipe (@pipeline) {
    #     printf(HDL " pipe %s", $pipe);
    # }

    # my $dmp = $dirsmgr->getDMPending();
    # my @pending = $dmp->reportMFZStats();
    # for my $pend (@pending) {
    #     printf(HDL " trad %s", $pend);
    # }

    print HDL "\n"x(12-$count);

    close HDL or die "Can't close $path: $!";
}

sub update {
    my __PACKAGE__ $self = shift or die;
    $self->captureBulkIOStats();
    $self->writeBulkIOStats();
    return 0; 
}

sub onTimeout {
    my ($self) = @_;
    DPPushPrefix($self->getTag());
    $self->update();
    DPPopPrefix(); 
}

1;
