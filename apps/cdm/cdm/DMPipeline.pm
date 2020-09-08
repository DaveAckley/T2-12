## Module stuff
package DMPipeline;
use strict;
use base 'DirectoryManager';
use fields qw(
    );

use Exporter qw(import);

our @EXPORT_OK = qw();
our %EXPORT_TAGS;

## Imports
use Constants qw(:all);
use DP qw(:all);
use PacketCDM_PF;

## Methods
sub new {
    my ($class,$cdm,$dirsmgr) = @_;
    defined $cdm or die;
    my $self = fields::new($class);
    $self->SUPER::new(SUBDIR_PIPELINE,$cdm,$dirsmgr);

    return $self;
}

sub newContentStub {
    my __PACKAGE__ $self = shift or die;
    my PacketCDM_PF $pfpkt = shift or die;
    my $spkt = $pfpkt->{mSPacket} or die;
    my $cn = $spkt->getContentName();
    die " $cn already exists" if defined $self->getMFZMgr($cn); #TMPipeline::handleAnnouncement should have avoided this

    my $mgr = MFZManager->new($cn,$self->{mCDM});
    $self->insertMFZMgr($mgr);
    $mgr->configureFromPFPacket($pfpkt);
}


sub update {
    my ($self) = @_;
    $self->SUPER::update();
    DPSTD("NNNNEEP");
}

1;
