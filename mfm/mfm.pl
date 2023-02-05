#!/usr/bin/perl -w

$| = 1; # Autoflush (we sleep in loops)

# Load physics config or hang waiting for it.
my $CONFIG_FILE = '/home/t2/CONFIG-T2/04/CONFIG-PHYSICS.dat';
my $MFM_SLOT = "03";
my $MFM_TAG_FILE = "/cdm/tags/slot$MFM_SLOT-install-tag.dat";

sub readFile {
    my $file = shift;
    my $wait = 0;
    while (!-r $file) {
        printf("WAITING FOR $file (%dmin)\n",$wait/60)
            unless $wait % 60;
        sleep 10;
        $wait += 10;
    }
    open FILE, "<", $file or die "$!";
    my $rec = <FILE>;
    chomp $rec;
    close FILE or die "$!";
    return $rec;
}

sub oneTry {
    my $mfmTag = readFile($MFM_TAG_FILE);
    $mfmTag =~ s/[^0-9a-f]//g;

    my $slot = readFile($CONFIG_FILE);
    $slot =~ s/[^0-9a-f]//g;

    print "MFM:$mfmTag SLOT PHYSICS:$slot\n";

    my $libcue = "/cdm/physics/slot$slot-installed-libcue.so";
    return undef
        unless -r $libcue; # Hmm?
    my $tagfile = "/cdm/tags/slot$slot-install-tag.dat";
    my $stamp = undef;
    if (open(FH,"<",$tagfile)) {
        $stamp = <FH>;
        chomp $stamp;
        $stamp =~ s/[^0-9a-f]//g;
        close(FH);
    }
    return ($mfmTag,$slot,$libcue,$stamp);
}

sub runMFMT2 {
    my ($mfmTag,$slot,$ep,$stamp) = @_;
    return undef
        unless
        defined $mfmTag and
        defined $slot and
        defined $ep and
        defined $stamp;
    my $id = "$MFM_SLOT-$mfmTag-$slot-$stamp"; # Sun Feb  5 10:38:31 2023 match mfm tags or NOT COMPATIBLE
    my $cmd = "/home/t2/MFM/bin/mfmt2 -t=1 -w /home/t2/MFM/res/mfmt2/wconfig.txt -z $id -e$ep";
    print "RUNNING $cmd\n";
    my $status = `$cmd`;
    print "EXIT STATUS $status\n";
}

sub main {
    print "ENTERED $0\n";
    while (1) {
        my @args = oneTry();
        if (defined $args[0]) {
            runMFMT2(@args);
            sleep 5;
        } else {
            print "INIT FAILURE, WAITING\n";
            sleep 60;
        }
    }
}
main();


