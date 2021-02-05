## Module stuff
package PacketCDM_C; 
use strict;
use base 'PacketCDM';
use fields qw(
    mSlotStamp
    mFilePosition
    );

use Exporter qw(import);

our @EXPORT_OK = qw();
our %EXPORT_TAGS;

## Imports
use Constants qw(:all);
use DP qw(:all);
use T2Utils qw(:all);

use MFZModel;

BEGIN { push @Packable::PACKABLE_CLASSES, __PACKAGE__ }

### CLASS METHOD
sub makeFromMFZModel {  # return a new C pkt or undef if no usable servers available
    my $class = shift || die;
    my MFZModel $model = shift || die;

    my $dir8 = $model->selectServableD8();
    return undef unless defined $dir8; 

    my $cpkt = $class->new();
    $cpkt->setDir8($dir8);
    $cpkt->{mSlotStamp} = $model->{mSlotStamp};
    $cpkt->{mFilePosition} = $model->pendingLength();

    return $cpkt;
}

### CLASS METHOD
sub recognize {
    my ($class,$packet) = @_;
    return $class->SUPER::recognize($packet)
        && $packet =~ /^..C/;
}

##VIRTUAL
sub packFormatAndVars {
    my ($self) = @_;
    my ($parentfmt,@parentvars) = $self->SUPER::packFormatAndVars();
    my ($myfmt,@myvars) =
        ("N N", 
         \$self->{mSlotStamp},
         \$self->{mFilePosition}
        );

    return ($parentfmt.$myfmt,
            @parentvars, @myvars);
}

##VIRTUAL
sub validate {
    my ($self) = @_;
    my $ret = $self->SUPER::validate();
    return $ret if defined $ret;
    return "Bad C command '$self->{mCmd}'"
        unless $self->{mCmd} eq "C";
    return "Bad SS in C packet"
        unless $self->{mSlotStamp} != 0;
    return "Missing file position"
        unless $self->{mFilePosition} >= 0;
    return undef;
}

##VIRTUAL
sub handleInbound {
    my __PACKAGE__ $self = shift or die;
    my CDM $cdm = shift or die;
    my $cmgr = $cdm->{mContentManager} or die;
    $cmgr->sendDataChunk($self); 
}

## Methods
sub new {
    my ($class) = @_;
    my $self = fields::new($class);
    $self->SUPER::new();
    $self->{mCmd} = "C";

    $self->{mSlotStamp} = 0; # Illegal value
    $self->{mFilePosition} = -1; # Illegal value
    return $self;
}

1;

