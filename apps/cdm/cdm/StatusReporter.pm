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
use TimeQueue qw(now);

use constant REC_DIR8 => 0;
use constant REC_TOTIN => REC_DIR8+1;
use constant REC_TOTOUT => REC_TOTIN+1;
use constant REC_FASTIN => REC_TOTOUT+1;
use constant REC_FASTOUT => REC_FASTIN+1;
use constant REC_SLOWIN => REC_FASTOUT+1;
use constant REC_SLOWOUT => REC_SLOWIN+1;
use constant REC_COUNT => REC_SLOWOUT+1;
use constant FAST_FRAC_OLD => 0.85;
use constant FAST_FRAC_NEW => 1-FAST_FRAC_OLD;
use constant SLOW_FRAC_OLD => 0.98;
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
    $self->defaultInterval(5); # Run about every 10 seconds if nothing happening

    return $self;
}

sub captureBulkIOStats {
    my __PACKAGE__ $self = shift or die;
    $self->{mLastSampleTime} = now() - 1 unless defined;
    my $diffsec = 0;
    my $now = now();
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
                my $sample = $diffin / $diffsec;
                $rec->[REC_FASTIN] = defined($rec->[REC_FASTIN]) ? FAST_FRAC_OLD * $rec->[REC_FASTIN] + FAST_FRAC_NEW * $sample : $sample;
                $rec->[REC_SLOWIN] = defined($rec->[REC_SLOWIN]) ? SLOW_FRAC_OLD * $rec->[REC_SLOWIN] + SLOW_FRAC_NEW * $sample : $sample;
                $rec->[REC_FASTOUT] = defined($rec->[REC_FASTOUT]) ? FAST_FRAC_OLD * $rec->[REC_FASTOUT] + FAST_FRAC_NEW * $sample : $sample;
                $rec->[REC_SLOWOUT] = defined($rec->[REC_SLOWOUT]) ? SLOW_FRAC_OLD * $rec->[REC_SLOWOUT] + SLOW_FRAC_NEW * $sample : $sample;
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

sub writeBulkIOStats {
    my __PACKAGE__ $self = shift or die;
    my $uptime = $self->{mLastSampleTime} - $self->{mInitTime};
    my $basedir = $self->{mCDM}->{mBaseDirectory};
    my $path = "$basedir/${\PATH_BASEDIR_REPORT_IOSTATS}";
    open HDL, ">", $path or die "Can't write $path: $!";
    print HDL "CDM UPTIME ".formatSeconds($uptime)."\n";
    for my $dir6 (getDir6s()) {
        my $dir8 = mapDir6ToDir8($dir6);
        my $rec = $self->{mRatesDir8}->{$dir8};
        my ($infast,$inslow,$outfast,$outslow) =
            (int($rec->[REC_FASTIN]+.5), int($rec->[REC_SLOWIN]+.5),
             int($rec->[REC_FASTOUT]+.5), int($rec->[REC_SLOWOUT]+.5));
        next if $infast==0 && $inslow==0 && $outfast==0 && $outslow==0;
        printf(HDL " %s i[%4d %4d] o[%4d %4d]\n",
               getDir8Name($dir8),$infast,$inslow,$outfast,$outslow
            );
    }

    my $dmpipe =  $self->{mCDM}->{mInPipelineContent};
    my @pipeline = $dmpipe->reportMFZStats();
    for my $pipe (@pipeline) {
        printf(HDL " pipe %s", $pipe);
    }

    my $dmp = $self->{mCDM}->{mPendingContent};
    my @pending = $dmp->reportMFZStats();
    for my $pend (@pending) {
        printf(HDL " trad %s", $pend);
    }

    print HDL "\n"x12;

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
