## Module stuff
package HookManager;
use strict;
use base 'TimeoutAble';
use fields qw(
    mHookMap
    );

use Exporter qw(import);
BEGIN {
my @HOOK_ACTIONS = qw(
    HOOK_ACTION_RESTART_MFMT2
    HOOK_ACTION_REBOOT
    HOOK_ACTION_RESTART_CDM
    );

our @EXPORT_OK = (@HOOK_ACTIONS);

our %EXPORT_TAGS = (
    actions => \@HOOK_ACTIONS,
    all => \@EXPORT_OK
    );
}
## Imports
use File::Copy; # For move
use MFZManager;
use Hooks;
use T2Utils qw(:all);

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

sub runHooks {
    my __PACKAGE__ $self = shift or die;
    my $hooktype = shift or die;
    my MFZManager $mgr = shift or die;
    my $cn = $mgr->{mContentName};
    my $cnmap = $self->{mHookMap}->{$cn};
    return undef unless defined $cnmap;
    my $aref = $cnmap->{$hooktype};
    return undef unless defined $aref;
    for my $hook (@$aref) {
        DPSTD("Running $cn $hooktype hook");
        DPPushPrefix("$hooktype $mgr->{mContentName}");
        my $ret = &{$hook}($mgr, $hooktype, $self);
        DPPopPrefix();
        return $ret if $ret;
    }
    return undef;
}

## HOOK METHODS return undef on success (if they return at all)
##CLASS METHOD: 
sub HOOK_ACTION_RESTART_MFMT2 {
    my $cmd = "pkill -f mfmt2";
    return !runCommandWithSync($cmd,"restart mfmt2");
}

##CLASS METHOD: (Never returns)
sub HOOK_ACTION_REBOOT {
    runCommandWithSync("systemctl reboot","reboot");
    while (1) {
        sleep 10; 
        DPSTD("WHY ARE WE STILL HERE?  WE SHOULD BE LONG DEAD BY NOW");
        runCommandWithSync("reboot","reboot harder");
    }
}

##CLASS METHOD: (Never returns)
sub HOOK_ACTION_RESTART_CDM {
    DPSTD("EXITTING BY REQUEST OF HOOK ACTION");
    exit 0;
}

sub registerHookActions {
    my __PACKAGE__ $self = shift;
    my $hookType = shift or die;
    my $cn = shift or die;
    my @actions = @_;

    my $cnmap = $self->{mHookMap}->{$cn};
    unless (defined $cnmap) {
        $cnmap = { };
        $self->{mHookMap}->{$cn} = $cnmap;
    }
    my $old = $cnmap->{$hookType};
    if (defined($old)) {
        DPSTD("Replacing existing $cn $hookType hook actions");
    }
    $cnmap->{$hookType} = \@actions;
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
