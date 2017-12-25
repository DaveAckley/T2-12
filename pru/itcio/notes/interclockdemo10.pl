#!/usr/bin/perl -Tw

my (%pru0, %pru1);

sub initPru {
    my ($hr, $cxd, @bitsToSend) = @_;
    $hr->{txrdy} = 0;
    $hr->{txdat} = 0;
    $hr->{desiredclockxor} = $cxd;
    $hr->{state} = 0;
    $hr->{output} = \@bitsToSend;
    $hr->{input} = [];
    
}

sub presentNextBit {
    my $hr = shift;
    if (scalar(@{$hr->{output}})) {
        my $next = shift @{$hr->{output}};
        $hr->{txdat} = $next;
    }
}

sub captureNextBit {
    my ($hr, $theirdat) = @_;
    push @{$hr->{input}}, $theirdat;
}

sub updatePru {
    my ($hrme, $hrother) = @_;
    if ($hrme->{state} == 0) { # low state

        my $xor = $hrme->{txrdy} ^ $hrother->{txrdy};
        if ($xor != $hrme->{desiredclockxor}) {

            captureNextBit($hrme,$hrother->{txdat});
            # XXX do rising business
            $hrme->{txrdy} = 1;
            $hrme->{state} = 1;

            reportPrus();
        }
        
    } elsif ($hrme->{state} == 1) {

        my $xor = $hrme->{txrdy} ^ $hrother->{txrdy};
        if ($xor != $hrme->{desiredclockxor}) {

            presentNextBit($hrme);
            # XXX do falling business
            $hrme->{txrdy} = 0;
            $hrme->{state} = 0;

            reportPrus();
        }


    } else {
        die "what";
    }
}

sub stringPru {
    my $hr = shift;
    my $out = sprintf("%d %d %d [%s][%s]%s",
                      $hr->{state},
                      $hr->{txrdy},
                      $hr->{txdat},
                      join("",@{$hr->{output}}),
                      join("",@{$hr->{input}}),
                      $hr->{state}==0?" ":"");
    return $out;
}

sub reportPrus {
    printf ("%s %s\n",stringPru(\%pru0), stringPru(\%pru1));
}

initPru(\%pru0, 0, 1,0,1,0,1,0,1,0,1,0);

initPru(\%pru1, 1, 1,1,1,0,0,0,1,1,0,0);


for (my $i = 0; $i < 100; ++$i) {
    if (rand() < 0.5) {
        updatePru(\%pru0,\%pru1);
    } else {
        updatePru(\%pru1,\%pru0);
    }
}
