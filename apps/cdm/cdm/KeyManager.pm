## Module stuff
package KeyManager;
use strict;
use base 'TimeoutAble';
use fields qw(
    mRegnum
    mHandle
    mPubKey
    mRSAPub
    );

use Exporter qw(import);

our @EXPORT_OK = qw();
our %EXPORT_TAGS;

## Imports
use Constants qw(:all);
use DP qw(:all);
use T2Utils qw(:all);

use lib "/home/t2/MFM/res/perllib";
use MFZUtils qw(:all);

## PRIVATE CLASS DATA

## Methods
sub new {
    my __PACKAGE__ $self = shift or die;
    my $cdm = shift or die;
    my $regnum = shift;
    die "Bad regnum" unless $regnum >= 0 && $regnum <= 0xffff;
    my ($num, $handle) = GetLegalRegnum($regnum);
    UntaintHandleIfLegal(\$handle);
    unless (ref $self) {
        $self = fields::new($self); # really a class
    }
    $self->SUPER::new("KM",$cdm);
    $self->defaultInterval(-120); # Run about every 60 seconds if nothing happening
    $self->{mRegnum} = $num;
    $self->{mHandle} = $handle;
    $self->{mRSAPub} = undef; # set by init()

    return $self;
}

sub init {
    my __PACKAGE__ $self = shift or die;

    my $cm = $self->{mCDM}->{mCryptoManager} or die;
    my ($pubkey,$fingerprint) = ReadPublicKeyFile($self->{mHandle});

    my $rsapub = Crypt::OpenSSL::RSA->new_public_key($pubkey);
    $rsapub->use_pkcs1_padding();
    $rsapub->use_sha512_hash();
    $self->{mRSAPub} = $rsapub;
}

sub verifySignature {
    my __PACKAGE__ $self = shift or die;
    my $data = shift or die;
    my $sig = shift or die;
    
    return $self->{mRSAPub}->verify($data,$sig);
}

1;
