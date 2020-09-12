## Module stuff
package K2M;
use strict;
use fields qw(
    mD9
    mCN
    );

use Exporter qw(import);

our @EXPORT_OK = qw();
our %EXPORT_TAGS;

## Imports
use Constants qw(:all);
use DP qw(:all);
use T2Utils qw(:all);

## Methods
sub new {
    my K2M $self = shift;
    unless (ref $self) {
        $self = fields::new($self);
    }
    $self->{mD9} = -1; # Illegal value
    $self->{mCN} = ""; # Illegal value
    return $self;
}

##PURE VIRTUAL METHOD
sub getK2 {
    my K2M $self = shift or die;
    ## Subclasses supply second key for metadata indexing
    die "NOT OVERRIDDEN";
}

1;
