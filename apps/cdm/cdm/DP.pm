## Module stuff
package DP;
use strict;
use constant DP => "DP";
use Exporter qw(import);

my @constants = qw(
    DEBUG_FLAG_PACKETS
    DEBUG_FLAG_DEBUG
    DEBUG_FLAG_STANDARD
    DEBUG_FLAG_VERBOSE
    DEBUG_FLAG_STACK_PREFIX
    DEBUG_FLAG_SAVE_TMP_DIRS
    DEBUG_FLAG_ALL
    );
my @functions = qw(
    DPF DPPKT DPSTD DPVRB DPDBG
    DPDIE
    DPSetLog DPSetFlags DPClearFlags
    DPGetPrefix DPPushPrefix DPPopPrefix
    DPANYFLAGS
    FUNCNAME
    );

our @EXPORT_OK = (@functions, @constants);
our %EXPORT_TAGS =
    (
     functions => \@functions,
     flags => \@constants,
     all => \@EXPORT_OK
    );


use constant DEBUG_FLAG_PACKETS => 1;
use constant DEBUG_FLAG_DEBUG => DEBUG_FLAG_PACKETS<<1;
use constant DEBUG_FLAG_STANDARD => DEBUG_FLAG_DEBUG<<1;
use constant DEBUG_FLAG_VERBOSE => DEBUG_FLAG_STANDARD<<1;
use constant DEBUG_FLAG_STACK_PREFIX => DEBUG_FLAG_VERBOSE<<1;
use constant DEBUG_FLAG_SAVE_TMP_DIRS => DEBUG_FLAG_STACK_PREFIX<<1;
use constant DEBUG_FLAG_ALL => 0xffffffff;

my $DEBUG_FLAGS = DEBUG_FLAG_STANDARD; ## = DEBUG_FLAG_ALL

my @PREFS = ();

my $TARGET = \*STDOUT;

sub DPANYFLAGS {
    return $DEBUG_FLAGS & shift;
}

sub DPF {
    my ($flags,$msg) = @_;
    return unless DPANYFLAGS($flags);
    print $TARGET DPGetPrefix().$msg."\n";
    return undef;
}

sub DPDIE {
    my ($msg) = @_;
    print $TARGET DPGetPrefix().$msg."\n";
    die $msg;
}

sub DPSetLog {
    my $old = $TARGET;
    $TARGET = shift;
    return $old;
}
 
sub DPSetFlags {
    my $old = $DEBUG_FLAGS;
    my $flags = shift;
    $DEBUG_FLAGS |= $flags;
    return $old;
}

sub DPClearFlags {
    my $old = $DEBUG_FLAGS;
    $DEBUG_FLAGS &= ~shift;
    return $old;
}
 
sub DPGetPrefix {
    my $len = scalar(@PREFS);
    return "" unless $len > 0;
    return join(":",@PREFS).": "
        if DPANYFLAGS(DEBUG_FLAG_STACK_PREFIX);
    return $PREFS[scalar(@PREFS)-1].": "
}

sub DPPushPrefix {
    push @PREFS, shift;
    DPSetFlags(DEBUG_FLAG_STACK_PREFIX);
#    print "DDD(".scalar(@PREFS).":".join(",, ",@PREFS).")\n";
}

sub DPPopPrefix {
    pop @PREFS;
}

sub DPPKT { DPF(DEBUG_FLAG_PACKETS,shift); }
sub DPSTD { DPF(DEBUG_FLAG_STANDARD,shift); }
sub DPVRB { DPF(DEBUG_FLAG_VERBOSE,shift); }
sub DPDBG { DPF(DEBUG_FLAG_DEBUG,shift); }

sub FUNCNAME {
    my $depth = shift;
    $depth = 1 unless defined $depth;
    return (caller($depth))[3];
}

1;
