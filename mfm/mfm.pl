#!/usr/bin/perl -w

# Load physics config or hang waiting for it.
my $CONFIG_FILE = '/home/t2/CONFIG-T2/04/CONFIG-PHYSICS.dat';

sub oneTry {
    my $wait = 0;
    while (!-r $CONFIG_FILE) {
        printf("WAITING FOR $CONFIG_FILE (%dmin)\n",$wait/60)
            unless $wait % 60;
        sleep 10;
        $wait += 10;
    }

    open CFG, "<", $CONFIG_FILE or die "$!";
    my $rec = <CFG>;
    chomp $rec;
    my $slot = 'ef'; # default
    if ($rec =~ /^([[:xdigit:]]{2})$/) {
        $slot = $1;
    } else {
        print "'$rec' ignored: Not recognized as slot\n";
    }
    print "SLOT PHYSICS $slot\n";
    my $libcue = "/cdm/physics/slot$slot-installed-libcue.so";
    return undef
        unless -r $libcue; # Hmm?
    my $tagfile = "/cdm/tags/slot$slot-install-tag.dat";
    my $stamp = undef;
    if (open(FH,"<",$tagfile)) {
        $stamp = <FH>;
        chomp $stamp;
        close(FH);
    }
    return ($slot,$libcue,$stamp);
}

sub runMFMT2 {
    my ($slot,$ep,$stamp) = @_;
    my $id = $slot;
    $id .= "-$stamp" if defined($stamp);
    my $cmd = "/home/t2/MFM/bin/mfmt2 -t=1 -w /home/t2/MFM/res/mfmt2/wconfig.txt -z $id -e$ep";
    print "RUNNING $cmd\n";
    my $status = `$cmd`;
    print "EXIT STATUS $status\n";
}

sub main {
    print "ENTERED $0\n";
    while (1) {
        my ($slot,$ep,$stamp) = oneTry();
        if (defined $ep) {
            runMFMT2($slot,$ep,$stamp);
        } else {
            print "INIT FAILURE, WAITING\n";
            sleep 60;
        }
    }
}
main();


