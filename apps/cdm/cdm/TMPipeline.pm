## Module stuff
package TMPipeline;
use strict;
use base 'TransferManager';
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
    $self->SUPER::new("ppln",$cdm);
    $self->defaultInterval(-20); # Run about every 10 seconds if nothing happening

    return $self;
}

sub update {
    my ($self) = @_;
    return 1 if $self->SUPER::update();
    DPSTD(__PACKAGE__." NNNNEEP ");
}

1;
