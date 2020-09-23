## Module stuff
package DeletedMap;
use strict;
use base 'Packable';
use fields qw(
    mVerMagic
    mRegnum
    mSigningSlotStamp
    mReserved
    mFlagStampMap
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
        && $pk =~ /^DMP1.\n/;
}

##CLASS METHOD
# Returns instance of DeletedMap, or undef and sets $@
sub initFromS01MFZ {
    my $mfzpath = shift || die;
    my $outer = LoadOuterMFZToMemory($mfzpath); 
    return undef unless defined $outer;  # $@ already set
    my $inner = LoadInnerMFZToMemory($outer); ## COUNTS ON SetKeyDir($basedir) ALREADY DONE
    return undef unless defined $inner;  # $@ already set

    ## MFZ_PUBKEY_NAME handle is locally known valid as of now
    my $mfzSigningHandle = $inner->[4];
    my $innerpathsref = $inner->[3];

    my ($dmpath, $dmname, $dmtime, $dmdata) = FindName($innerpathsref,DELETEDS_MAP_NAME,undef);

    my $dmref = Packable::parse($dmdata);
    return undef unless defined $dmref; # $@ already set
    return SetError("Not a DeletedMap") unless $dmref->isa('DeletedMap');
    
    return $dmref;
}

# return undef and set $@ if map sig bad, else return successful handle
sub verifySignature {
    my __PACKAGE__ $self = shift;
    return SetError("Bad pack") unless
        defined $self->{mPacketBytes} &&
        length($self->{mPacketBytes}) == DELETED_MAP_FULL_FILE_LENGTH;
    my $regnum = $self->{mRegnum}; defined $regnum or die;
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

    my ($data,$sig) = unpack(DELETED_MAP_FULL_FILE_FORMAT,$self->{mPacketBytes});

    return SetError("DMP10 header failed verification via '$handle'")
        unless $rsapub->verify($data,$sig);
    return $handle;
}

##VIRTUAL
sub packFormatAndVars {
    my __PACKAGE__ $self = shift;
    my ($parentfmt,@parentvars) = $self->SUPER::packFormatAndVars();
    my @fsmaprefs = map { \$_ } @{$self->{mFlagStampMap}};
    my ($myfmt,@myvars) =
        (DELETED_MAP_SIGNED_DATA_FORMAT."a*", # Use a* to handle signed or unsigned..
         \$self->{mVerMagic},
         \$self->{mRegnum},
         \$self->{mSigningSlotStamp},
         \$self->{mReserved},
         @fsmaprefs,
         \$self->{mSignature}
        );

    return ($parentfmt.$myfmt,
            @parentvars, @myvars);
}

##VIRTUAL METHOD
sub postunpack {
    my __PACKAGE__ $self = shift or die;
    $self->SUPER::postunpack();
}

##VIRTUAL
sub validate {
    my __PACKAGE__ $self = shift;
    my $ret = $self->SUPER::validate();
    return $ret
        if defined $ret;
    return "Bad vermagic '$self->{mVerMagic}'"
        unless $self->{mVerMagic} =~ /^DMP1.\n/;
    return "Bad regnum"
        unless $self->{mRegnum} >= 0 && $self->{mRegnum} <= 255;
    return "Bad signing stamp"
        unless SSSlot($self->{mSigningSlotStamp}) == DELETED_SLOT_NUMBER;
    my $signtime = SSStamp($self->{mSigningSlotStamp});
    my $slot = 0;
    for my $fstamp (@{$self->{mFlagStampMap}}) {
        my ($flags,$stamp) = (SSSlot($fstamp),SSStamp($fstamp));
        return sprintf("Bad S%02x fstamp %06x (vs %06x)",$slot,$stamp,$signtime)
            unless $stamp <= $signtime; # Can't delete the future yo
        ++$slot;
    }
    return "Bad signature"
        unless length($self->{mSignature}) == 0  # unsigned
        || length($self->{mSignature}) == 128 ;  # signed

    return undef;
}

## Methods
sub new {
    my __PACKAGE__ $self = shift;
    unless (ref $self) {
        $self = fields::new($self);
    }
    $self->SUPER::new();

    $self->{mVerMagic} = "";           # Illegal value
    $self->{mRegnum} = -1;             # Illegal value
    $self->{mSigningSlotStamp} = -1;   # Illegal value
    $self->{mReserved} = undef;        # Illegal value
    $self->{mFlagStampMap} = [(0) x 256];  # Hopefully illegal values
    $self->{mSignature} = undef;      # Illegal value

    return $self;
}

sub slotRef {
    my __PACKAGE__ $self = shift || die;
    my $idx = shift; defined $idx || die;
    die if $idx < 0 || $idx > 255;
    return \$self->{mFlagStampMap}->[$idx];
}

sub slotFlags {
    my __PACKAGE__ $self = shift || die;
    my $idx = shift; defined $idx || die;
    my $optval = shift;
    return SSSlot($self->slotRef($idx),$optval);
}

sub slotStamp {
    my __PACKAGE__ $self = shift || die;
    my $idx = shift; defined $idx || die;
    my $optval = shift;
    return SSStamp($self->slotRef($idx),$optval);
}

sub init {
    my __PACKAGE__ $self = shift || die;

    $self->{mVerMagic} = "DMP10\n";     
    $self->{mReserved} = "";
    my $dslot = SSMake(DELETED_FLAG_SLOT_VALID,0);
    $self->{mFlagStampMap} = [($dslot) x 256];  # Valid, not deleted, no stamp
    $self->markChanged();
}

sub markChanged {
    my __PACKAGE__ $self = shift || die;
    $self->{mRegnum} = -1;           # Stays illegal until signed
    $self->{mSigningSlotStamp} = -1; # Stays illegal until signed
    $self->{mSignature} = "";        # Length 0 before signing
    $self->{mPacketBytes} = undef;   # Not packed
}

sub signDeletedMap {
    my __PACKAGE__ $self = shift || die;
    my $regnum = shift; defined $regnum || die;
    my $innertime = shift || die;

    my $handle = GetHandleIfLegalRegnum($regnum);
    die "$@" unless defined $handle;

    my $slot = DELETED_SLOT_NUMBER;
    my $privkeyfile = GetPrivateKeyFile($handle);
    $privkeyfile = ReadableFileOrDie("private key file", $privkeyfile);

    my ($stamp) = SSStampFromTime($innertime); 

    ## Finalize and pack the deleted map
    $self->{mRegnum} = $regnum;
    $self->{mSigningSlotStamp} = SSMake($slot,$stamp); 
    $self->{mSignature} = ""; # Empty sig contributes no bytes to data
    $self->pack(); # set mPacketBytes to data-to-be-signed
    die unless length($self->{mPacketBytes}) == DELETED_MAP_DATA_LENGTH;

    ## Sign and repack it
    my $signature = SignStringRaw($privkeyfile, $self->{mPacketBytes});
    die "Bad sign" unless length($signature) == 128;
    $self->{mSignature} = $signature;  # Stash signature
    $self->pack();                     # repack to get full format
    die unless length($self->{mPacketBytes}) == DELETED_MAP_FULL_FILE_LENGTH;

    return $self;
}



1;
