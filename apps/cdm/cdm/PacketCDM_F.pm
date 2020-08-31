## Module stuff
package PacketCDM_F; 
use strict;
use base 'PacketCDM';
use fields qw(
    mName
    mLength
    mChecksum
    mInnerTimestamp
    mSeqno
    );

use Exporter qw(import);

our @EXPORT_OK = qw();
our %EXPORT_TAGS;

## Imports
use Constants qw(:all);
use DP qw(:all);
use T2Utils qw(:all);

BEGIN { push @Packet::PACKET_CLASSES, __PACKAGE__ }

## Methods
sub new {
    my ($class) = @_;
    my $self = fields::new($class);
    $self->SUPER::new();
    $self->{mCmd} = "F";
    return $self;
}

### CLASS METHOD
sub recognize {
    my ($class,$packet) = @_;
    return $class->SUPER::recognize($packet)
        && $packet =~ /^..F/;
}

##VIRTUAL
sub packFormatAndVars {
    my __PACKAGE__ $self = shift;
    my ($parentfmt,@parentvars) = $self->SUPER::packFormatAndVars();
    my ($myfmt,@myvars) =
        ("C/a* C/a* C/a* C/a* C/a*",  # Lovely!
         \$self->{mName},
         \$self->{mLength},
         \$self->{mChecksum},
         \$self->{mInnerTimestamp},
         \$self->{mSeqno}
        );

    return ($parentfmt.$myfmt,
            @parentvars, @myvars);
}

##VIRTUAL
sub validate {
    my __PACKAGE__ $self = shift;
    my $ret = $self->SUPER::validate();
    return $ret
        if defined $ret;
    return "Bad F command '$self->{mCDMCmd}'"
        unless $self->{mCmd} eq "F";
    return "Content name '$self->{mName}' too long"
        unless length($self->{mName}) <= MAX_CONTENT_NAME_LENGTH;
    return "Missing length"
        unless $self->{mLength} > 0;
    return "Missing checksum"
        unless length($self->{mChecksum}) > 0;
    return "Missing inner timestamp"
        unless $self->{mInnerTimestamp} > 0;
    return "Missing or bad seqno"
        unless $self->{mSeqno} > 0;
    return undef;
}

sub matchesMFZ {
    my __PACKAGE__ $self = shift or die;
    my MFZManager $mgr = shift or return undef;

    return 0 unless $self->{mName} eq $mgr->{mContentName};
    return 0 unless $self->{mLength} eq $mgr->{mFileTotalLength};
    return 0 unless $self->{mChecksum} eq $mgr->{mFileTotalChecksum};
    return 0 unless $self->{mInnerTimestamp} eq $mgr->{mFileInnerTimestamp};
    return 1;  ## mSeqno NOT CHECKED
}

sub populateMFZMgr {
    my __PACKAGE__ $self = shift or die;
    my MFZManager $mgr = shift or die;
    die unless $self->{mName} eq $mgr->{mContentName}; # Only field that must be already set
    $mgr->{mFileTotalLength} = $self->{mLength};
    $mgr->{mFileTotalChecksum} = $self->{mChecksum};
    $mgr->{mFileInnerTimestamp} = $self->{mInnerTimestamp};
    return $self->{mSeqno};
}

##VIRTUAL
sub handleInbound {
    my __PACKAGE__ $self = shift;
    my CDM $cdm = shift;
    my $tm = $cdm->{mTraditionalManager} or die;
    return $tm->handleAnnouncement($self); 
}

1;

