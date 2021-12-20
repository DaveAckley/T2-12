## Module stuff
package CDMap;
use strict;
use base 'Packable';
use fields qw(
    mVerMagic
    mBlockSizeBits
    mRegnum
    mSlotStamp
    mMappedFileLength
    mLabel
    mMappedFileChecksum
    mIncrementalXsums
    mSignature
    );

use Exporter qw(import);

our @EXPORT_OK = qw();
our %EXPORT_TAGS;
use DP qw(:all);
use Constants qw(:all);
use T2Utils qw(:math :fileops);
use MFZUtils qw(:all);

BEGIN { push @Packable::PACKABLE_CLASSES, __PACKAGE__ }

### CLASS METHOD
sub recognize {
    my ($class,$pk) = @_;
    return $class->SUPER::recognize($pk)
        && $pk =~ /^CDM1.\n/;
}

sub getTotalLength {
    my __PACKAGE__ $self = shift;
    return $self->{mMappedFileLength} + CDM10_FULL_MAP_LENGTH;
}

# return undef and set $@ if map sig bad, else return successful handle
sub verifySignature {
    my __PACKAGE__ $self = shift;
    return SetError("Bad pack") unless
        defined $self->{mPacketBytes} &&
        length($self->{mPacketBytes}) == CDM10_FULL_MAP_LENGTH;
    my $regnum = $self->{mRegnum}; defined($regnum) or die;
    my $handle = GetHandleIfLegalRegnum($regnum);
    return SetError($@) unless defined $handle;
    my $pubkey = eval {
        my ($key, $fingerprint) = ReadPublicKeyFile($handle);
        $key;
    };
    return SetError("Can't read public key for '$handle'")
        unless defined($pubkey);
    my $rsapub = Crypt::OpenSSL::RSA->new_public_key($pubkey);
    $rsapub->use_pkcs1_padding();
    $rsapub->use_sha512_hash();

    my ($data,$sig) = unpack(CDM10_PACK_FULL_FILE_FORMAT,$self->{mPacketBytes});

    return SetError("CDM10 header failed verification via '$handle'")
        unless $rsapub->verify($data,$sig);
    return $handle;
}

##VIRTUAL
sub packFormatAndVars {
    my __PACKAGE__ $self = shift;
    my ($parentfmt,@parentvars) = $self->SUPER::packFormatAndVars();
    my @isumrefs = map { \$_ } @{$self->{mIncrementalXsums}};
    my ($myfmt,@myvars) =
        (CDM10_PACK_SIGNED_DATA_FORMAT."a128",
         \$self->{mVerMagic},
         \$self->{mBlockSizeBits},
         \$self->{mRegnum},
         \$self->{mSlotStamp},
         \$self->{mMappedFileLength},
         \$self->{mLabel},
         \$self->{mMappedFileChecksum},
         @isumrefs,
         \$self->{mSignature}
        );

    return ($parentfmt.$myfmt,
            @parentvars, @myvars);
}

##VIRTUAL METHOD
sub postunpack {
    my __PACKAGE__ $self = shift or die;
    $self->SUPER::postunpack();
    $self->{mLabel} =~ s/\0*$//; # Grr eat trailing nulls
}

##VIRTUAL
sub validate {
    my __PACKAGE__ $self = shift;
    my $ret = $self->SUPER::validate();
    return $ret
        if defined $ret;
    return "Bad vermagic '$self->{mVerMagic}'"
        unless $self->{mVerMagic} =~ /^CDM1.\n/;
    return "Bad block size bits"
        unless $self->{mBlockSizeBits} > 0;
    return "Bad regnum"
        unless $self->{mRegnum} >= 0 && $self->{mRegnum} <= 0xff;
    return "Bad slotstamp"
        unless $self->{mSlotStamp} > 0;
    return "Bad mapped file length"
        unless $self->{mMappedFileLength} > 0;
    return "Bad label"
        unless length($self->{mLabel}) <= 16;
    for my $xsum (@{$self->{mIncrementalXsums}}) {
        return "Bad xsum" unless length($xsum) == 8;
    }
    return "Bad signature"
        unless length($self->{mSignature}) == 128;
    return undef;
}

##CLASS METHOD
# return new CDMap or undef and set @! to error message
sub newFromPath {
    my $path = shift || die;
    open(HDL, "<", $path) or return SetError("Can't read $path: $!");
    my $map;
    my $len = read(HDL,$map,CDM10_FULL_MAP_LENGTH);
    close HDL or return SetError("Can't close $path: $!");
    return SetError("'$path' length $len too short")
        if $len < CDM10_FULL_MAP_LENGTH;
    my $cdmap = CDMap->new($map)
        or return SetError("$path bad map: $@");
    die "XXXX IFNISHIN ME";

}

## Methods
sub new {
    my __PACKAGE__ $self = shift;
    unless (ref $self) {
        $self = fields::new($self);
    }
    $self->SUPER::new();

    $self->{mVerMagic} = "";         # Illegal value
    $self->{mBlockSizeBits} = 0;     # Illegal value
    $self->{mRegnum} = -1;           # Illegal value
    $self->{mSlotStamp} = 0;         # Illegal value
    $self->{mMappedFileLength} = -1; # Illegal value
    $self->{mLabel} = undef;         # Illegal value
    $self->{mMappedFileChecksum} = undef; # Illegal value
    $self->{mIncrementalXsums} = [("")x100]; # Hopefully illegal values
    $self->{mSignature} = undef;     # Illegal value

    return $self;
}

1;
