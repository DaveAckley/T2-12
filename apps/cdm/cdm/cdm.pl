#!/usr/bin/perl -w  # -*- perl -*-
use File::Basename;
use Cwd qw(abs_path);
use lib dirname (abs_path(__FILE__));
use CDM;
use Constants qw(:all);
use DP qw(:all);

use PacketClasses;
use Hooks;

## Cleanliness stuff
use warnings FATAL => 'all';
$SIG{__DIE__} = sub {
    die @_ if $^S;
    require Carp; 
    Carp::confess ;
};

DPSetFlags(DEBUG_FLAG_STACK_PREFIX|DEBUG_FLAG_STANDARD);
DPSTD("$0 start");

my $cdm = CDM->new("./cdmDEBUG");
$cdm->init();
Hooks::installHooks($cdm);

my $dmc = $cdm->{mCompleteAndVerifiedContent};
DPPushPrefix("Preloading $dmc->{mDirectoryName}");
$dmc->loadAll();
DPPopPrefix();
#$cdm->loadDeleteds();

use Data::Dumper;
#print Dumper(\$cdm);

$cdm->eventLoop();

print "COUNT=".$cdm->update()."\n";

exit 0;

