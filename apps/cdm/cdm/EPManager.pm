## Module stuff
package EPManager;
use strict;
use strict 'refs';
use base 'TimeoutAble';
use fields (
    "mSocketPath",        # local unix domain socket path
    "mSocket",            # actual local unix domain listener
    "mEPs",               # fileno => EP
    "mKeyToEP",           # endpointkey => EP (after EP configured)
    );


use Exporter qw(import);

our @EXPORT_OK = qw();
our %EXPORT_TAGS;

## Imports
use Socket;
use IO::Socket::UNIX;

use T2Utils qw(:all);
use MFZUtils qw(:all);
use DP qw(:all);
use TimeQueue;
use Constants qw(:all);
use EP;

## Methods
sub new {
    my ($class,$cdm) = @_;
    defined $cdm or die;
    my $self = fields::new($class);
    $self->SUPER::new("EPManager",$cdm);
    my $sockdir = InitMFMSubDir(SUBDIR_SOCKETS);
    $self->{mSocketPath} = "$sockdir/${\PATH_SOCKETDIR_XFERSOCK}";
    $self->{mSocket} = undef;  
    $self->{mEPs} = { }; 
    $self->{mKeyToEP} = { }; 

    $self->{mCDM}->getTQ()->schedule($self);
    $self->defaultInterval(-1);
    return $self;
}

sub init {
    my ($self) = @_;
    my $cdm = $self->{mCDM};

    die unless defined $self->{mSocketPath};
    die "REINIT?" if defined $self->{mSocket};

    unlink $self->{mSocketPath};
    $self->{mSocket} = IO::Socket::UNIX->new(
        Type => SOCK_STREAM(),
        Local => $self->{mSocketPath},
        Listen => 1,
        ) or die "new: $@";

    unless (chmod(0777, $self->{mSocketPath}) == 1) { die "Can't chmod $self->{mSocketPath}: $!"; }
    $self->{mSocket}->blocking(0);

    $SIG{PIPE} = sub { DPSTD("CAUGHT SIGPIPE"); };

    DPSTD("Listening on $self->{mSocketPath}");
}

sub statusLines {
    my __PACKAGE__ $self = shift || die;
    my @lines;
    for my $epk (sort keys %{$self->{mKeyToEP}}) {
        my $ep = $self->{mKeyToEP}->{$epk};
        if (defined($ep)) {
            my $line = sprintf("%-10s %s",
                               formatEndpointKey($epk),
                               $ep->formatTraffic());
            push @lines, $line;
        }
    }
    return @lines;
}

# Confirm srpkt is an SR packet and ship it to route
sub sendSR {
    my __PACKAGE__ $self = shift || die;
    my PacketSR $srpkt = shift || die;
    my $route = shift || die;
    $srpkt->isa('PacketSR') or die;
    my $cdm = $self->{mCDM};
    $srpkt->{mRoute} = $route;
    return $srpkt->handleInbound($cdm);
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
    return $self->{mKeyToEP}->{$key};
}

#return 1 if registered successfully, 0 if endpoint already exists
sub registerClientServer {
   my __PACKAGE__ $self = shift || die;
   my EP $sre = shift || die;
   my $key = $sre->getKey();
   return 0 if defined $self->{mKeyToEP}->{$key};
   $self->{mKeyToEP}->{$key} = $sre;
   DPSTD("Registered EP ".formatEndpointKey($key));
   return 1;
}

# Forget everything about $ep
sub dropEP {
    my __PACKAGE__ $self = shift||die;
    my EP $ep = shift||die;
    my $socket = $ep->{mLocalCxn};
    my $fileno = fileno($socket);
    close $socket or
        DPSTD("WARNING: Close failed on $fileno: $!");
    my $key = $ep->getKey();   # Might be undef if setup failure
    delete $self->{mEPs}->{$fileno};
    delete $self->{mKeyToEP}->{$key} if defined $key;
}

sub update {
    my ($self) = @_;
    my $socket = $self->{mSocket};
    my $conn = $socket->accept();
    if (!defined $conn) {
        unless ($!{EAGAIN}) {  # No new connection
            die "accept: $!";
        }
    } else {
        DPSTD("CONNECTION ".fileno($conn)." from ".fileno($socket));
        $conn->blocking(0);
        my $ep = EP->new($self->{mCDM});
        $ep->init($conn,$self);
        $self->{mEPs}->{fileno($conn)} = $ep;
        $self->{mKeyToEP}->{fileno($conn)} = undef;
    }
}

sub onTimeout {
    my ($self) = @_;
    DPPushPrefix($self->getTag());
    $self->update();
    DPPopPrefix(); 
}

1;
