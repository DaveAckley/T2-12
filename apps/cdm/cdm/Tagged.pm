package Tagged;
use strict;
use fields qw(
    mCDM
    mNumber 
    mName 
    );
use Exporter qw(import);

our @EXPORT_OK = qw();
our %EXPORT_TAGS;

my $instances = 0;
sub new {
    my Tagged $self = shift;
    my $name = shift or die;
    my $cdm = shift or die;
    $cdm->isa("CDM") or die;
    unless (ref $self) {
        $self = fields::new($self);
    }
    $self->{mCDM} = $cdm;
    $self->{mNumber} = $instances++;
    $self->{mName} = $name;

    return $self;
}

sub getTag {
    my ($self) = @_;
    return $self->{mName}."#".$self->{mNumber};
}

sub getCDM {
    my ($self) = @_;
    return $self->{mCDM};
}

1;
