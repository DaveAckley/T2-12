## Module stuff
package Urgency;
use strict;
use base 'TimeoutAble';
use fields qw(
    mTCMap
    mOCMap
    );

use Exporter qw(import);

our @EXPORT_OK = qw();
our %EXPORT_TAGS;

use DP qw(:all);
use Constants qw(:all);
use T2Utils qw(:math :fileops :dirs);
use MFZUtils qw(:all);

## Methods
sub new {
    my ($class,$cdm) = @_;
    defined $cdm or die;
    my $self = fields::new($class);
    $self->SUPER::new("Urgency",$cdm);

    $self->{mTCMap} = { };    # { SLOT -> { ITC -> [TS LEN WHEN] } }
    $self->{mOCMap} = { };    # { SLOT -> [TS LEN WHEN] }

    $self->{mCDM}->getTQ()->unschedule($self);  # Letting ContentManger drive us

    return $self;
}

sub forgetAboutThem {
    my __PACKAGE__ $self = shift || die;
    my $dir8 = shift || die;
    for my $slot ($self->allMySlots()) {
        delete $self->{mTCMap}->{$slot}->{$dir8};
    }
    DPSTD("URGFORGOT ".getDir8Name($dir8));
}

sub iJustAnnouncedTo {
    my __PACKAGE__ $self = shift || die;
    my $slot = shift || die;
    my $dir8 = shift || die;
    my ($ts,$len) = @{$self->whatIKnow($slot)};
    return $self->iNowThinkTheyKnow($slot,$dir8,$ts,$len);
}

sub theyJustRequested {
    my __PACKAGE__ $self = shift || die;
    my $slot = shift || die;
    my $dir8 = shift || die;
    my $ts = shift || die;
    my $len = shift || 0; # ?? possible?
    return $self->iNowThinkTheyKnow($slot,$dir8,$ts,$len);
}

sub iNowThinkTheyKnow {
    my __PACKAGE__ $self = shift || die;
    my $slot = shift || die;
    my $dir8 = shift || die;
    my $ts = shift || die;
    my $len = shift || 0; # ?? possible?

    my $tr = $self->whatIThinkTheyKnow($slot,$dir8);
    if ($tr->[0] != $ts || $tr->[1] != $len) {
        $tr->[0] = $ts;
        $tr->[1] = $len;
        $tr->[2] = now();
        return 1;  # If anybody cares
    }
    return 0; # ditto
}

sub iJustGrewTo {
    my __PACKAGE__ $self = shift || die;
    my $slot = shift || die;
    my $ts = shift || die;
    my $len = shift || 0; # ?? possible?
    my $ir = $self->whatIKnow($slot);
    if ($ir->[0] != $ts || $ir->[1] != $len) {
        $ir->[0] = $ts;
        $ir->[1] = $len;
        $ir->[2] = now();
        return 1;
    }
    return 0;
}

sub whatIKnow {
    my __PACKAGE__ $self = shift || die;
    my $slot = shift || die;
    $self->{mOCMap}->{$slot} = [0, 0, 0]
        unless defined $self->{mOCMap}->{$slot};
    return $self->{mOCMap}->{$slot};
}

sub whatIThinkTheyKnow {
    my __PACKAGE__ $self = shift || die;
    my $slot = shift || die;
    my $dir8 = shift || die;
    $self->{mTCMap}->{$slot} = { } unless
        defined $self->{mTCMap}->{$slot};
    $self->{mTCMap}->{$slot}->{$dir8} = [0, 0, 0] unless
        defined $self->{mTCMap}->{$slot}->{$dir8};
    return $self->{mTCMap}->{$slot}->{$dir8};
}

sub getUrgency {
    my __PACKAGE__ $self = shift || die;
    my $slot = shift || die;
    my $dir8 = shift || die;
    my ($ourts,$ourlen,$ourwhen) = @{$self->whatIKnow($slot)};
    return 0 if $ourts == 0; # No urgency if we have nothing in SLOT
    my ($theyts, $theylen, $theywhen) =
        @{$self->whatIThinkTheyKnow($slot,$dir8)};
    ($theylen, $theywhen) = (0, 0)
        if $ourts != $theyts;   # Diff TS -> when is irrelevant
    my $timepressure = $self->logtime(now() - $theywhen);
    my $sizepressure = max(1, $ourlen - $theylen);
    return int($sizepressure * $timepressure);
}

sub logtime {
    my __PACKAGE__ $self = shift || die;
    my $secs = shift || 0;
    return 0 if $secs < 6;
    return 1 if $secs < 60;
    return 2 if $secs < 3600;
    return 3;
}

sub allMySlots {
    my __PACKAGE__ $self = shift || die;
    return keys %{$self->{mOCMap}};
}

sub maybeAnnounceSomething {
    my __PACKAGE__ $self = shift || die;
    my ContentManager $cm = shift || die;
    my $URG_BASELINE = 500; # MIN 1! Units of bytes*logtime 
    my $toturg = $URG_BASELINE;
    my ($pickslot,$pickitc,$pickurg);
    my $nhm = $self->{mCDM}->{mNeighborhoodManager};
    my @ngbmgrs = $nhm->getNgbMgrs();
    for my $nm (@ngbmgrs) {
        next unless $nm->isOpen();
        for my $slot ($self->allMySlots()) {
            my $dir8 = $nm->{mDir8}; # So never will be 0 in T2
            my $thisurg = $self->getUrgency($slot,$dir8);
            $toturg += $thisurg;
            DPDBG(sprintf("URG1 %02x->%s %9d", $slot, getDir8Name($dir8), $thisurg));
            ($pickslot,$pickitc,$pickurg) = ($slot,$dir8,$thisurg)
                if oddsOf($thisurg, $toturg);
        }
    }
    if (defined($pickslot)) {
        DPSTD(sprintf("URGANN %02x->%s %9d %9d", $pickslot, getDir8Name($pickitc), $pickurg, $toturg - $pickurg));
        my $model = $cm->getDominantMFZModelForSlot($pickslot,DOM_ONLY_MAPPED);
        my $ngb = $nhm->ngbMgr(mapDir8ToDir6($pickitc));
        DPSTD("NO MODEL FOR SLOT $pickslot?") unless defined $model;
        DPSTD("NO NGBMGR FOR ITC $pickitc?") unless defined $ngb;
        $cm->trySendAnnouncement($model,$ngb->{mDir8})
            if defined($model) && defined($ngb);
        return 1; # I had a pick (whether it really shipped or not)
    }
    return 0;  # I had nothing urgent to say
}

sub maybeAnnounceSomeThings {
    my __PACKAGE__ $self = shift || die;
    my ContentManager $cm = shift || die;
    my $TRIES = 3;
    for (my $try = 0; $try < $TRIES; ++$try) {
        last unless $self->maybeAnnounceSomething($cm);
    }
}

sub update {
    my __PACKAGE__ $self = shift || die;
    my ContentManager $cm = shift || die;
    DPPushPrefix($self->getTag());
    $self->maybeAnnounceSomething($cm);
    DPPopPrefix(); 
}

1;
