package TimeoutAble;
use strict;
use base 'Tagged';
use fields qw(
    mWhen 
    mDefaultInterval
    mTQIndex 
    mLastTQ
    );
use Exporter qw(import);

use DP qw(:all);

our @EXPORT_OK = qw();
our %EXPORT_TAGS;

my $instances = 0;
sub new {
    my __PACKAGE__ $self = shift;
    my $name = shift or die;
    my $cdm = shift or die;
    $cdm->isa("CDM") or die;
    unless (ref $self) {
        $self = fields::new($self);
    }
    $self->SUPER::new($name,$cdm);
    $self->{mWhen} = -1;
    $self->{mTQIndex} = -1;
    $self->{mDefaultInterval} = undef; # Doesn't reschedule automatically by default
    $self->{mLastTQ} = undef;

    return $self;
}

sub defaultInterval {
    my $self = shift;
    $self->{mDefaultInterval} = shift
        if defined $_[0];
    return $self->{mDefaultInterval};
}

sub expires {
    my ($self) = @_;
    return $self->{mWhen};
}

sub unschedule {
    my ($self) = @_;
    my $tq = $self->{mLastTQ};
    $tq->remove($self) if defined $tq;
}

sub wakeup { shift->reschedule(0); }

sub reschedule {
    my ($self,$secsdelay) = @_;
    die unless defined $self->{mLastTQ};
    $self->{mLastTQ}->schedule($self,$secsdelay);
}

sub onTimeout {
    my ($self) = @_;
    DPPushPrefix($self->getTag());
    DPDIE("onTimeout not overridden by ".ref $self);
    DPPopPrefix();
}

1;
