## Module stuff
package DMCommon;
use strict;
use base 'DirectoryManager';
use fields qw(
    mDeletedsMap
    );

use Exporter qw(import);

our @EXPORT_OK = qw();
our %EXPORT_TAGS;

## Imports
use Constants qw(:all);
use DP qw(:all);
use HookManager;

## Methods
sub new {
    my ($class,$cdm,$dirsmgr) = @_;
    defined $cdm or die;
    my $self = fields::new($class);
    $self->SUPER::new(SUBDIR_COMMON,$cdm,$dirsmgr);
    $self->{mDeletedsMap} = { }; # { cn -> [ cn len cksum innerts ] }
    return $self;
}

sub isDeleted {
    my __PACKAGE__ $self = shift or die;
    my $cn = shift or die;
    my $innertimestamp = shift or die;
    my $rec = $self->{mDeletedsMap}->{$cn};
    return 0 unless defined $rec;
    return $innertimestamp <= $rec->[3];
}

##OVERRIDE
sub notifyTransferManagers {
    my __PACKAGE__ $self = shift or die;
    my MFZManager $mgr = shift or die;
    ##DMCommon notifies both TMTrad and TMPipe
    my $cdm = $self->{mCDM};
    $cdm->{mTraditionalManager}->setupMetadata(DIR8_SERVER, $mgr);
    $cdm->{mPipelineManager}->setupMetadata(DIR8_SERVER, $mgr);
}

#@Override
sub newContent {
    my ($self,$nextname) = @_;
    my $mgr = MFZManager->new($nextname,$self->{mCDM});
    $self->insertMFZMgr($mgr);
    if ($mgr->loadCnVMFZ()) {
        my $hkm = $self->{mCDM}->{mHookManager};
        $hkm->runHooks(HOOK_TYPE_LOAD,$mgr);
        $hkm->runHooks(HOOK_TYPE_RELEASE,$mgr);
        DPSTD("Managing ".$mgr->getTag());
    } else {
        DPSTD("Invalid ".$mgr->getTag());
    }
}

sub update {
    my ($self) = @_;
    return 1 if $self->SUPER::update();
    DPSTD(FUNCNAME);
}


1;
