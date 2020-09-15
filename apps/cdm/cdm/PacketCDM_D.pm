## Module stuff
package PacketCDM_D; 
use strict;
use base 'PacketCDM';
use fields qw(
    mSlotStamp
    mFilePosition
    mData
    mHack16
    );

use Exporter qw(import);

our @EXPORT_OK = qw();
our %EXPORT_TAGS;

## Imports
use Constants qw(:all);
use DP qw(:all);
use T2Utils qw(:all);

BEGIN { push @Packable::PACKABLE_CLASSES, __PACKAGE__ }

### CLASS METHOD
sub makeFromCPktAndData {
    my $cpkt = shift || die;
    my $data = shift; die unless defined $data;
    my $dpkt = PacketCDM_D->new();
    $dpkt->setDir8($cpkt->getDir8());
    $dpkt->{mSlotStamp} = $cpkt->{mSlotStamp};
    $dpkt->{mFilePosition} = $cpkt->{mFilePosition};
    $dpkt->{mData} = $data;
    return $dpkt;
}

## Methods
sub new {
    my ($class) = @_;
    my $self = fields::new($class);
    $self->SUPER::new();
    $self->{mCmd} = "D";

    $self->{mSlotStamp} = 0;     # Illegal value
    $self->{mFilePosition} = -1; # Illegal value
    $self->{mData} = undef;      # Illegal value
    $self->{mHack16} = undef;    # Illegal value
    return $self;
}

### CLASS METHOD
sub recognize {
    my ($class,$packet) = @_;
    return $class->SUPER::recognize($packet)
        && $packet =~ /^..D/;
}

##VIRTUAL
sub prepack {
    my __PACKAGE__ $self = shift or die;
    $self->{mHack16} = hack16($self->{mData});
}

##VIRTUAL
sub packFormatAndVars {
    my ($self) = @_;
    my ($parentfmt,@parentvars) = $self->SUPER::packFormatAndVars();
    my ($myfmt,@myvars) =
        ("N N C/a* a2", 
         \$self->{mSlotStamp},
         \$self->{mFilePosition},
         \$self->{mData},
         \$self->{mHack16} 
        );

    return ($parentfmt.$myfmt,
            @parentvars, @myvars);
}

##VIRTUAL
sub validate {
    my ($self) = @_;
    my $ret = $self->SUPER::validate();
    return $ret if defined $ret;
    return "Bad D command '$self->{mCmd}'"
        unless $self->{mCmd} eq "D";
    return "Missing SS in D packet"
        unless $self->{mSlotStamp} != 0;
    return "Bad file position"
        unless $self->{mFilePosition} >= 0;
    return "Missing data'"
        unless defined($self->{mData});
    return "Missing hack16"
        unless defined($self->{mHack16});
    return "Bad hack16"
        unless hack16($self->{mData}) eq $self->{mHack16};
    return undef;
}

##VIRTUAL
sub handleInbound {
    my __PACKAGE__ $self = shift or die;
    my CDM $cdm = shift or die;
    my $cmgr = $cdm->{mContentManager} or die;
    return $cmgr->handleDataChunk($self); 
}

1;

