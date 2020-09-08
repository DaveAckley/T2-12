## Module stuff
package DMPending;
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

## Methods
sub new {
    my ($class,$cdm,$dirsmgr) = @_;
    defined $cdm or die;
    my $self = fields::new($class);
    $self->SUPER::new(SUBDIR_PENDING,$cdm,$dirsmgr);
    DPSTD("${\FUNCNAME} $self dp($self->{mDirectoryPath})");

    return $self;
}

## VIRTUAL
sub newContent {
    my __PACKAGE__ $self = shift;
    my $cname = shift or die;
    my $mgr = MFZManager->new($cname,$self->getCDM());
    $self->insertMFZMgr($mgr);
    
    return $mgr;
}

sub update {
    my ($self) = @_;
    $self->SUPER::update();
    DPSTD("NNNNEEP");
}

1;
