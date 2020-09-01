package TimeQueue;
use strict;
use fields qw(
    mCreationTime
    mTimeoutAbles
    mCount);
use Exporter qw(import);

use DP qw(:all);

my @timefuncs = qw(
    now
    ago
    aged
    );

our @EXPORT_OK = (@timefuncs);

our %EXPORT_TAGS = (
    timefuncs => \@timefuncs,
    all => \@EXPORT_OK
    );

use Time::HiRes qw(sleep time);
    
sub new {
    my TimeQueue $self = shift;
    unless (ref $self) {
        $self = fields::new($self);
    }
    $self->{mCreationTime} = now();
    $self->{mTimeoutAbles} = [];
    $self->{mCount} = 0;
    return $self;
}

sub now {
    return time();
}

sub ago {
    my $when = shift;
    return now() - $when;
}

sub aged {
    my ($when,$age) = @_;
    return ago($when) >= $age;
}

sub insert {
    my ($self,$to) = @_;
    die unless $to->isa('TimeoutAble');
    my $idx = $to->{mTQIndex};
    if ($idx < 0) {
        $idx = $self->{mCount}++;
        $self->{mTimeoutAbles}->[$idx] = $to;
        $to->{mTQIndex} = $idx;
        $to->{mLastTQ} = $self;
    } elsif ($to->{mLastTQ} != $self) {  # If on a TQ, it must be us
        DPDIE("Cross TQ insert");
    }
}

sub remove {
    my ($self,$to) = @_;
    die unless $to->isa('TimeoutAble');
    my $idx = $to->{mTQIndex};
    if ($idx >= 0) {
        die unless $to == $self->{mTimeoutAbles}->[$idx];
        die unless $self->{mCount} > 0;
        my $lastIdx = --$self->{mCount};
        if ($idx != $lastIdx) {
            my $tomove = $self->{mTimeoutAbles}->[$lastIdx];
            $self->{mTimeoutAbles}->[$idx] = $tomove;
            $tomove->{mTQIndex} = $idx;
        }
        $to->{mTQIndex} = -1;
    }
}

sub schedule {
    my ($self,$to,$secsdelay) = @_;
    $secsdelay = -5 unless defined $secsdelay; # random 0..4 if not supplied
    $secsdelay = rand(-$secsdelay) if $secsdelay < 0;
    die unless $to->isa('TimeoutAble');
    $self->insert($to);
    my $now = $self->now();
    $to->{mWhen} = $now + $secsdelay;
#    DPDBG($to->getTag()." ($now/$secsdelay) when now ".$to->{mWhen});
}

sub unschedule {
    remove(@_);
}

sub runEvent {
    my ($self,$max) = @_;
    my $now = now();
    my $count = 0;
    my $nearestUnexpired;
    DPPushPrefix(sprintf("%.2f",$now-$self->{mCreationTime}));
    # 'Priority queue'
    my ($min,$minto);
    for (my $idx = 0; $idx < $self->{mCount}; ++$idx) {
        my $to = $self->{mTimeoutAbles}->[$idx];
        my $when = $to->expires();
        #DPDBG("Considering ".$to->getTag()." at $when (now=$now)");

        if ($when < $now) {
            #DPDBG("Eligible at $when (now=$now)");
            ($min,$minto) = ($when,$to)
                if !defined($min) || ($when < $min);
        } elsif (!defined($nearestUnexpired) || $when < $nearestUnexpired) {
            $nearestUnexpired = $when;
        }
    }
    if (defined $minto) {
        $self->unschedule($minto);  # must reschedule if it wants to live
        my $interval = $minto->{mDefaultInterval};  # which it can do by default
        $minto->reschedule($interval) if defined $interval;

        DPDBG("Running ".$minto->getTag());
        $minto->onTimeout();
    }
    DPPopPrefix();
    return (!defined($minto) && defined($nearestUnexpired)) ? $nearestUnexpired - $now : 0;
}

1;
