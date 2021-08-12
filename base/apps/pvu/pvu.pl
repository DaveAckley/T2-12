#!/usr/bin/perl -w

use strict;
use Curses;

use Time::HiRes qw ( time alarm sleep );
use Data::Dumper;


my @dir8names = ('NT','NE','ET','SE','ST','SW','WT','NW');

sub startCurses {
    initscr();
    noecho();
    cbreak();
    nodelay(1);
    $SIG{INT} = sub { done("^C") };
}

sub done { endwin(); print "@_\n"; exit; }

sub mainLoop {
    my $count;
    my $timeout = 0.25;
    while (1) {
        while ((my $key = getch()) ne ERR) {    # maybe multiple keys
            if ($key eq 'q') { done("See ya"); }
            elsif ($key eq 'l') { erase(); }
            elsif ($key eq 'n') { nextRate(); }
            elsif ($key eq 'p') { prevRate(); }
        }
        my @data = split(/\n/,gatherOutput());
        for (my $i = 0; $i < $LINES; $i++) {
            addstr($i, 0, $data[$i] || ' ' x $COLS);
        }

        addstr(0,0,formatTau());
        addstr(1,0,formatRate());
        standout();
        addstr($LINES-1, $COLS - 32, (scalar localtime)." ".++$count);
        standend();

        move(0,0);
        refresh();                              # flush new output to display

        my ($in, $out) = ('', '');
        vec($in,fileno(STDIN),1) = 1;           # look for key on stdin
        select($out = $in,undef,undef,$timeout);# wait up to this long
    }
}

sub gatherOutput {
    return updateITCPKTStats();
}

sub main {
    startCurses();
    mainLoop();
    done("Done");
}

##################
my %ITCstats = ();

my $backavgidx = 0;
#perl -e '$dt=1;$tau = 300;printf("%f\n",exp(-$dt/$tau))'
my @timeconstantssec = (5,10,60,300,900);
sub alphafortau {
    my $tau = shift;
    my $dt = 1; # 1 sample/sec
    return exp(-$dt/$tau);
}
my @rateprotos =
    map { [alphafortau($_)] } @timeconstantssec;

sub getTau {
    return $timeconstantssec[$backavgidx];
}

sub nextRate {
    $backavgidx = 0 if ++$backavgidx >= scalar(@rateprotos);
    return getRate();
}
sub prevRate {
    $backavgidx = scalar(@rateprotos) - 1 if --$backavgidx < 0;
    return getRate();
}
sub getRate {
    return $rateprotos[$backavgidx]->[0];
}
sub formatTau {
    my $tau = getTau();
    return sprintf("%2dsec",$tau) if $tau < 99;
    return sprintf("%2dmin",int($tau/60)) if $tau < 60*99;
    return sprintf("%2dhr ",int($tau/(60*60))) if $tau < 60*60*99;
    return sprintf("%2dday",int($tau/(60*60*24)));
}

sub formatRate {
    return sprintf("%4.3f",getRate());
}

sub getStatForTypeAndDir {
    my $type = shift;
    my $ret = [$type]; # mfm, blk, tot
    push @$ret, [];    # last sample: time bo bi po pi
    foreach my $rate (@rateprotos) {
        push @$ret, [@$rate]; # backavgs
    }
    return $ret;
}

#     return
#         [$type,  
#          [],     
#          [.80],  # backavg: rate bo bi po pi
#          [.90],  # backavg
#          [.99],  # backavg
#         ]; #
# }
sub updateITCStatsSample {
    my ($lastsample,$bo,$bi,$po,$pi) = @_;
    my $now = time();
    my $lastnow = $lastsample->[0];
    my $delta = undef;
    if (defined($lastnow) && $lastnow + 1 <= $now) {
        my $secs = $now - $lastnow;
        $delta = [
            ($bo - $lastsample->[1])/$secs,
            ($bi - $lastsample->[2])/$secs,
            ($po - $lastsample->[3])/$secs,
            ($pi - $lastsample->[4])/$secs,
            ];
        $lastnow = undef;
    }
    if (!defined($lastnow)) {
        $lastsample->[0] = $now;
        $lastsample->[1] = $bo;
        $lastsample->[2] = $bi;
        $lastsample->[3] = $po;
        $lastsample->[4] = $pi;
    }
    return $delta;
}
sub updateITCBackavg {
    my ($backavginfo,$delta) = @_;
    my $old = $backavginfo->[0];
    my $new = 1-$old;
    if (!defined($backavginfo->[1])) {
        push @{$backavginfo}, @{$delta};
    } else {
        $backavginfo->[1] = $old*$backavginfo->[1] + $new*$delta->[0];
        $backavginfo->[2] = $old*$backavginfo->[2] + $new*$delta->[1];
        $backavginfo->[3] = $old*$backavginfo->[3] + $new*$delta->[2];
        $backavginfo->[4] = $old*$backavginfo->[4] + $new*$delta->[3];
    }
}
sub updateITCSourceStats {
    my ($source, $bo, $bi, $po, $pi) = @_;
    my $delta = updateITCStatsSample($source->[1],$bo,$bi,$po,$pi);
    return unless defined $delta;
    for (my $rate = 0; $rate < scalar(@rateprotos); $rate++) {
        my $idx = $rate + 2;
        updateITCBackavg($source->[$idx],$delta);
    }
}
sub formatDir8 {
    my $dir8 = shift;
    die "($dir8)?" unless defined $dir8names[$dir8];
    return $dir8names[$dir8];
}
sub formatKBps {
    my ($rate) = @_;
    return sprintf("%4.1f",$rate/1000.0);
}
sub formatPkps {
    my ($rate) = @_;
    return sprintf("%3.0f",$rate);
}
sub formatRates {
    my $ratevec = shift;
    my $idx = $backavgidx + 2;
    return "" unless defined $ratevec and defined $ratevec->[$idx] and defined $ratevec->[$idx]->[1];
    my $bpp = -1;
    my $totpps = $ratevec->[$idx]->[3] + $ratevec->[$idx]->[4];
    if ($totpps > 0) {
        my $totbps = $ratevec->[$idx]->[1] + $ratevec->[$idx]->[2];
        $bpp = $totbps/$totpps;
    }
    return $ratevec->[0]. #mfm/blk/tot
        formatKBps($ratevec->[$idx]->[1])." ".
        formatKBps($ratevec->[$idx]->[2])." ".
        formatPkps($ratevec->[$idx]->[3])." ".
        formatPkps($ratevec->[$idx]->[4])." ".
        sprintf("%3d",int($bpp));
}
sub formatITCDirStats {
    my $itcstats = shift;
    my $ret = "";
#    print STDERR Dumper($itcstats);
    $ret .= formatDir8($itcstats->{dir});
    $ret .= "[".formatRates($itcstats->{mfm})."]";
    $ret .= "[".formatRates($itcstats->{blk})."]";
    $ret .= "[".formatRates($itcstats->{tot})."]";
    return $ret;
    # my %idxnames = ( 1 => 'mi', 2 => 'mo', 3 => 'bi', 4 => 'bo');
    # for (my $idx = 1; $idx < 5; ++$idx) {
    #     $ret .= $idxnames{$idx};
    #     $ret .= "[".formatRate($idx
    # }
    # $ret .= " ".formatRates($itcstats->{mfm}
}
sub updateITCStats {
    my ($itcs,@data) = @_;
    my ($mbo,$mbi,$mpo,$mpi,$bbo,$bbi,$bpo,$bpi) = @data;
    updateITCSourceStats($itcs->{mfm},$mbo,$mbi,$mpo,$mpi);
    updateITCSourceStats($itcs->{blk},$bbo,$bbi,$bpo,$bpi);
    updateITCSourceStats($itcs->{tot},$mbo+$bbo,$mbi+$bbi,$mpo+$bpo,$mpi+$bpi);
    # print STDERR Dumper($itcs);
}
sub getITCStats {
    my $dir = shift;
    my $itcs = $ITCstats{$dir};
    if (!defined $itcs) {
        $itcs = {
            dir => $dir,
            mfm => getStatForTypeAndDir('mfm'),
            tot => getStatForTypeAndDir('tot'),
            blk => getStatForTypeAndDir('blk'),
        };
        $ITCstats{$dir} = $itcs;
    }
    return $itcs;
}
my @ls =                        
    (                           
     "     KB   KB   pkt pkt avg",
     "     /s   /s   /s  /s  len",
     "     out  in   out in  o+i",
    );                          
my $toplabel =
    "  ".($ls[0] x 3)."\n".
    "  ".($ls[1] x 3)."\n".
    "  ".($ls[2] x 3)."\n"; 

sub formatITCPktStats {
    my $ret = $toplabel;
    for (my $dir8 = 0; $dir8 < 8; ++$dir8) {
        next if $dir8 == 0 || $dir8 == 4;
        my $itcs = getITCStats($dir8);
#        $ret .= Dumper($itcs);
        $ret .= formatITCDirStats($itcs);
        $ret .= "\n";
    }
    return $ret;
}

sub updateITCPKTStats {
    open(HANDLE,"<","/sys/class/itc_pkt/statistics") or die;
    my @lines = <HANDLE>;
    close(HANDLE) or die;
    chomp @lines;
    die unless shift @lines eq 'dir psan sfan toan mfmbsent mfmbrcvd mfmpsent mfmprcvd svcbsent svcbrcvd svcpsent svcprcvd';
    while (my $row = shift @lines) {
        my ($dir,$ps,$sf,$to,@data) = split(/\s+/,$row);
        my $itcs = getITCStats($dir);
        updateITCStats($itcs,@data);
    }
    return formatITCPktStats();
}

main();
