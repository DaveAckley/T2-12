## Module stuff
package PacketCDM_S; 
use strict;
use base 'PacketCDM';
use fields qw(
    mAnnounceVersion
    mInnerTimestamp
    mInnerLength
    mRegnum
    mInnerChecksumPrefix
    mContentStem
    mPayload
    mRSASig
    );

use Exporter qw(import);

our @EXPORT_OK = qw();
our %EXPORT_TAGS;

## Imports
use Constants qw(:all);
use DP qw(:all);
use T2Utils qw(:all);
use CryptoManager;
use KeyManager;

BEGIN { push @Packet::PACKET_CLASSES, __PACKAGE__ }

## Methods
sub new {
    my ($class) = @_;
    my $self = fields::new($class);
    $self->SUPER::new();
    $self->{mCmd} = "S";
    return $self;
}

### CLASS METHOD
sub recognize {
    my ($class,$packet) = @_;
    return $class->SUPER::recognize($packet)
        && $packet =~ /^..S/;
}

##VIRTUAL
sub postunpack {
    my PacketCDM_S $self = shift or die;
    $self->{mContentStem} =~ s/\0*$//; # Grr eat trailing nulls
    $self->{mPayload} = substr($self->{mPacketBytes},0,ANNOUNCE_PACKET_DATA_LENGTH);
}

##VIRTUAL
sub packFormatAndVars {
    my __PACKAGE__ $self = shift;
    my ($parentfmt,@parentvars) = $self->SUPER::packFormatAndVars();
    my ($myfmt,@myvars) =
        (ANNOUNCE_S_PACK_DATA_FORMAT
         ."a128",                   # RSA sig
         \$self->{mAnnounceVersion},
         \$self->{mInnerTimestamp},
         \$self->{mInnerLength},
         \$self->{mRegnum},
         \$self->{mInnerChecksumPrefix},
         \$self->{mContentStem},
         \$self->{mRSASig}
        );

    my $fmt = $parentfmt.$myfmt;
    my @vars = (@parentvars, @myvars);
    #DPSTD("FMT $fmt");
    #DPSTD("VARS ".join(", ",@vars));
    
    return ($fmt, @vars);
}

##VIRTUAL
sub validate {
    my __PACKAGE__ $self = shift;
    my $ret = $self->SUPER::validate();
    return $ret
        if defined $ret;
    return "Bad S command '$self->{mCDMCmd}'"
        unless $self->{mCmd} eq "S";
    return "Version '$self->{mAnnounceVersion}' not handled"
        unless $self->{mAnnounceVersion} == 2;
    return "Invalid inner length"
        unless $self->{mInnerLength} > 0;
    return "Invalid regnum"
        unless $self->{mRegnum} >= 0 && $self->{mRegnum} <= 0xffff;
    return "Bad checksum prefix"
        unless length($self->{mInnerChecksumPrefix}) == 8;
    return "Missing or bad content stem"
        unless $self->{mContentStem} =~ /^[-_.a-zA-Z0-9]+$/;
    return undef;
}

sub verifySignature {
    my __PACKAGE__ $self = shift;
    my CDM $cdm = shift or die;
    my CryptoManager $cm = $cdm->{mCryptoManager};
    my $regnum = $self->{mRegnum};
    my $km = $cm->getKeyMgrIfAny($regnum);
    unless (defined $km) {
        $@ = "Verification failed: Unrecognized or revoked regnum '$regnum'";
        return 0;
    }
    my $data = $self->{mPayload};  
    substr($data,0,1) = chr(0x80);  # Clean up the packet header (nuke source dir etc)
    unless ($km->verifySignature($data, $self->{mRSASig})) {
        $@ = "Verification failed: Bad/corrupt data/signature";
        return 0;
    }
    return 1;
}

sub getContentName {
    my __PACKAGE__ $self = shift;
    return $self->{mContentStem}.".mfz";
}

# sub matchesMFZ {
#     my __PACKAGE__ $self = shift or die;
#     my MFZManager $mgr = shift or return undef;

#     return 0 unless $self->{mName} eq $mgr->{mContentName};
#     return 0 unless $self->{mLength} eq $mgr->{mFileTotalLength};
#     return 0 unless $self->{mChecksum} eq $mgr->{mFileTotalChecksum};
#     return 0 unless $self->{mInnerTimestamp} eq $mgr->{mFileInnerTimestamp};
#     return 1;  ## mSeqno NOT CHECKED
# }

##VIRTUAL
sub handleInbound {
    my __PACKAGE__ $self = shift;
    return DPSTD("Ignored unwrapped ".$self->summarize());
}

1;

