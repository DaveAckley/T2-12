## Module stuff
package CryptoManager;
use strict;
use base 'TimeoutAble';
use fields qw(
    mKeyDir
    mRegnumHandles
    );

use Exporter qw(import);

our @EXPORT_OK = qw();
our %EXPORT_TAGS;

## Imports

use lib "/home/t2/MFM/res/perllib";
use MFZUtils qw(:all);

use List::Util qw(shuffle);
use DP qw(:all);
use Constants qw(DIR8_SERVER);
use T2Utils qw(:dirs);
use KeyManager;

## Methods
sub new {
    my __PACKAGE__ $self = shift;
    my $cdm = shift;
    defined $cdm or die;

    my $keydir = shift;
    $keydir = "/cdm" unless defined $keydir;

    unless (ref $self) {
        $self = fields::new($self); # really a class
    }

    $self->SUPER::new("CryptM",$cdm);

    $self->{mRegnumHandles} = { };  # { regnum -> keymgr }
    $self->{mKeyDir} = $keydir;

    $self->{mCDM}->getTQ()->schedule($self);
    $self->defaultInterval(-120); # Run about every 60 seconds if nothing happening

    return $self;
}

sub populateRegnums {
    my __PACKAGE__ $self = shift or die;
    for my $regnum (GetValidRegnums()) {
        my $km = KeyManager->new($self->{mCDM}, $regnum);
        $km->init();
        $self->{mRegnumHandles}->{$regnum} = $km;
    }
}

##VIRTUAL
sub init {
    my ($self) = @_;
    SetKeyDir($self->{mKeyDir});
    $self->populateRegnums();
}

sub getPublicKeyDir {
    return GetPublicKeyDir();
}

sub getKeyMgr {
    my __PACKAGE__ $self = shift or die;
    my $regnum = shift;
    my $ret = $self->getKeyMgrIfAny($regnum);
    die "Undefined regnum '$regnum'" unless defined $ret;
    return $ret;
}

sub getKeyMgrIfAny {
    my __PACKAGE__ $self = shift or die;
    my $regnum = shift;
    my $ret = $self->{mRegnumHandles}->{$regnum};
    return $ret;
}

sub update {
    my ($self) = @_;
    # XXX
    return 0; 
}

sub onTimeout {
    my ($self) = @_;
    DPPushPrefix($self->getTag());
    $self->update();
    DPPopPrefix(); 
}

1;
