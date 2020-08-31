## Module stuff
package HookManager;
use strict;
use base 'TimeoutAble';
use fields qw(
    mHookMap
    );

use Exporter qw(import);

our @EXPORT_OK = qw();
our %EXPORT_TAGS;

## Imports
use File::Copy; # For move
use MFZManager;
use Hooks;

use DP qw(:all);


## Methods
sub new {
    my HookManager $self = shift;
    my $cdm = shift or die;
    unless (ref $self) {
        $self = fields::new($self); # really a class
    }
    $self->SUPER::new("RelMgr",$cdm);

    $self->{mHookMap} = {}; # { cn -> { hooktype -> \&hooksub } }

    $self->{mCDM}->getTQ()->schedule($self);

    return $self;
}

sub runHookIfAny {
    my __PACKAGE__ $self = shift or die;
    my $hooktype = shift or die;
    my MFZManager $mgr = shift or die;
    my $cn = $mgr->{mContentName};
    my $cnmap = $self->{mHookMap}->{$cn};
    return undef unless defined $cnmap;
    my $hook = $cnmap->{$hooktype};
    return undef unless defined $hook;
    DPSTD("Running $cn $hooktype hook");
    DPPushPrefix("$hooktype $mgr->{mContentName}");
    my $ret = &{$hook}($mgr, $hooktype, $self);
    DPPopPrefix();
    return $ret;
}

sub registerHook {
    my __PACKAGE__ $self = shift;
    my $hookType = shift or die;
    my $cn = shift or die;
    my $hook = shift or die;
    my $cnmap = $self->{mHookMap}->{$cn};
    unless (defined $cnmap) {
        $cnmap = { };
        $self->{mHookMap}->{$cn} = $cnmap;
    }
    my $old = $cnmap->{$hookType};
    if (defined($old)) {
        DPSTD("Replacing existing $cn $hookType hook")
            if $hook != $old;
    }
    $cnmap->{$hookType} = $hook;
    DPSTD("Registered $cn $hookType hook");
}

sub update {
    my ($self) = @_;
    $self->reschedule(-20);
    return 1; # 'Did something'?
}

sub onTimeout {
    my ($self) = @_;
    DPPushPrefix($self->getTag());
    $self->update();
    DPPopPrefix(); 
}

1;
