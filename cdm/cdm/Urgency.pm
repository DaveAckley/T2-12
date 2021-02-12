## Module stuff
package Urgency;
use strict;
use base 'TimeoutAble';
use fields qw(
    mUMap
    );

use Exporter qw(import);

our @EXPORT_OK = qw();
our %EXPORT_TAGS;

use DP qw(:all);
use Constants qw(:all);
use T2Utils qw(:math :fileops);
use MFZUtils qw(:all);

## Methods
sub new {
    my ($class,$cdm) = @_;
    defined $dir or die;
    my $self = fields::new($class);
    $self->SUPER::new("Urgency",$cdm);

    $self->{mUMap} = { };    # { slotnum -> { ITC -> [THEM US] } }
                             # THEM|US: [TIMESTAMP GOODLEN LASTTIME]

    $self->{mCDM}->getTQ()->schedule($self);
    $self->defaultInterval(-4); # Run about every 2 seconds if nothing happening

    return $self;
}

sub iJustAnnouncedTo {
    my __PACKAGE__ $self = shift || die;
    my $slot = shift || die;
    my $stamp = shift || die;
    my $len = shift || die;
    my $dir6 = shift || die;
    die "IMPLEMENT ME";
}

sub maybeAnnounceSomething {
    my __PACKAGE__ $self = shift || die;

    die "IMPLEMENT ME";
}

sub maybeRequestSomething {
    my __PACKAGE__ $self = shift || die;
    die "IMPLEMENT ME";
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
