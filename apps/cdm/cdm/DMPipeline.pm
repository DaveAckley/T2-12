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

## Methods
sub new {
    my ($class,$cdm) = @_;
    defined $cdm or die;
    my $self = fields::new($class);
    $self->SUPER::new(SUBDIR_PIPELINE,$cdm);

    return $self;
}

sub update {
    my ($self) = @_;
    $self->SUPER::update();
    DPSTD("NNNNEEP");
}

1;
