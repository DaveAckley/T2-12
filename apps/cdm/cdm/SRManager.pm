## Module stuff
package SRManager;
use strict;
use strict 'refs';
use base 'TimeoutAble';
use fields qw(
    mSocketPath
    mSelect
    mSocket
    mEndpoints
    mUsers
    );

use Exporter qw(import);

our @EXPORT_OK = qw();
our %EXPORT_TAGS;

## Imports
use Socket;
use IO::Select;
use IO::Socket::UNIX;
use List::Util qw(shuffle);

use T2Utils qw(:all);
use MFZUtils qw(:all);
use DP qw(:all);
use TimeQueue;
use Constants qw(:all);
use PacketClasses;
use PacketSR;

use SREndpoint;

## Methods
sub new {
    my ($class,$cdm) = @_;
    defined $cdm or die;
    my $self = fields::new($class);
    $self->SUPER::new("SRManager",$cdm);
    my $sockdir = InitMFMSubDir(SUBDIR_SOCKETS);
    $self->{mSocketPath} = "$sockdir/${\PATH_SOCKETDIR_XFERSOCK}";
    $self->{mSocket} = undef;  # Illegal value
    $self->{mSelect} = undef;  # Illegal value
    $self->{mEndpoints} = { }; # srekey -> SREndpoint (when network side open)
    $self->{mUsers} = { };  # fileno -> SREndpoint (when user side open)

    $self->{mCDM}->getTQ()->schedule($self);
    $self->defaultInterval(-1);
    return $self;
}

sub init {
    my ($self) = @_;
    my $cdm = $self->{mCDM};

    die "REINIT?" if defined $self->{mSelect};
    $self->{mSelect} = IO::Select->new();

    die unless defined $self->{mSocketPath};
    unlink $self->{mSocketPath};
    $self->{mSocket} = IO::Socket::UNIX->new(
        Type => SOCK_STREAM(),
        Local => $self->{mSocketPath},
        Listen => 1,
        ) or die "new: $@";
    DPSTD("Listening on $self->{mSocketPath}");
    $self->{mSelect}->add($self->{mSocket});
}

sub getServerIfAny {
    my __PACKAGE__ $self = shift || die;
    my $route = shift || die;
    my ($x,$y) = collapseRouteToCoord($route);
    my $key = packEndpointKey(0,$x,$y);
    return $self->getEndpointIfAnyFromKey($key);
}

sub getClientIfAny {
    my __PACKAGE__ $self = shift || die;
    my $route = shift || die;
    my ($x,$y) = collapseRouteToCoord($route);
    my $key = packEndpointKey(1,$x,$y);
    return $self->getEndpointIfAnyFromKey($key);
}

sub getEndpointIfAnyFromKey {
    my __PACKAGE__ $self = shift || die;
    my $key = shift || die;
    return $self->{mEndpoints}->{$key};
}

sub openLocal {
    my __PACKAGE__ $self = shift || die;
    my $conn = shift || die;
    my $fileno = fileno($conn);
    die if defined($self->{mUsers}->{$fileno});  # fileno in use?  we messed up

    my $sre = SREndpoint->new($self->{mCDM});

    $sre->init();
    $sre->connectLocal($conn);
    $self->{mUsers}->{$fileno} = $sre;
    $self->{mSelect}->add($conn);
}

sub registerClientServer {
   my __PACKAGE__ $self = shift || die;
   my SREndpoint $sre = shift || die;
   my $key = $sre->getKey();
   die if defined $self->{mEndpoints}->{$key};
   $self->{mEndpoints}->{$key} = $sre;
   my ($isclient,$x,$y) = unpackEndpointKey($key);
   DPSTD("Registered SRE ($isclient,$x,$y)");
}

sub closeLocal {
    my __PACKAGE__ $self = shift || die;
    my $conn = shift || die;
    my $msg = shift; # undef ok
    my $fileno = fileno($conn);
    my $sre = $self->{mUsers}->{$fileno};
    return unless defined($sre);

    print $conn "$msg\n" if defined $msg;
    $sre->disconnectLocal();
    delete $self->{mUsers}->{$fileno};
    $self->{mSelect}->remove($conn);
    $conn->close() or die "Can't close $conn: $!";
}

sub sendSR {
    my __PACKAGE__ $self = shift || die;
    my PacketSR $srpkt = shift || die;
    my $route = shift || die;
    $srpkt->isa('PacketSR') or die;
    my $cdm = $self->{mCDM};
    $srpkt->{mRoute} = $route;
    return $srpkt->handleInbound($cdm);
}

sub updateRead {
    my __PACKAGE__ $self = shift || die;
    my @ready = $self->{mSelect}->can_read(0.0);
    for my $fh (@ready) {
        if ($fh == $self->{mSocket}) {  # new connect
            my $conn = $self->{mSocket}->accept();
            $self->openLocal($conn);
        } else {    # input on existing
            my $fileno = fileno($fh);
            my $sre = $self->{mUsers}->{$fileno};
            if (defined($sre)) {
                if (!$sre->readUser()) {
                    $self->closeLocal($fh);
                }
            } else {
                DPSTD("No sre for $fileno/read?");
            }
        }                
    }
}

sub updateWrite {
    my __PACKAGE__ $self = shift || die;
    my @ready = $self->{mSelect}->can_write(0.0);
    for my $fh (@ready) {
        my $fileno = fileno($fh);
        my $sre = $self->{mUsers}->{$fileno};
        if (defined($sre)) {
            $sre->tryToDeliverDataLocally();
        } else {
            DPSTD("No sre for $fileno/write?");
        }                
    }
}

sub update {
    my ($self) = @_;
    $self->updateRead();  # Read local
    $self->updateWrite();  # Write local
}

sub onTimeout {
    my ($self) = @_;
    DPPushPrefix($self->getTag());
    $self->update();
    DPPopPrefix(); 
}

1;
