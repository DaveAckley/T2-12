#!/usr/bin/perl -Tw

my (%pru0, %pru1);

sub initPru {
    my ($hr, $cxd, @bytesToSend) = @_;
    $hr->{txrdy} = 0;
    $hr->{txdat} = 0;
    $hr->{onessent} = 0;
    $hr->{onesrcvd} = 0;
    $hr->{desiredclockxor} = $cxd;
    $hr->{state} = 0;
    $hr->{output} = \@bytesToSend;
    $hr->{currentoutputbyte} = 0;
    $hr->{outputstuffed} = 1;
    $hr->{bitinoutputbyte} = 8;
    $hr->{currentinputbyte} = 0;
    $hr->{bitininputbyte} = 8;
    $hr->{bytesininputpacket} = 0;
    $hr->{packetsync} = 0;
    $hr->{input} = [];
    
}

sub getNextOutputByte {
    my $hr = shift;
    
    if (scalar(@{$hr->{output}})) {
        my $byte = ord(shift @{$hr->{output}});
        if ($byte > 0) {
            $hr->{currentoutputbyte} = $byte;
            $byte = $hr->{currentoutputbyte};
            $hr->{outputstuffed} = 1;
            return;
        }
    }
    $hr->{currentoutputbyte} = 0b01111110;
    $hr->{outputstuffed} = 0;
    return;
}

sub getBitInByte {
    my ($byte,$bit) = @_;
    return ($byte>>$bit)&1;
}

sub getNextStuffedBit {
    my $hr = shift;
    my $stuff = 1;
    if ($hr->{bitinoutputbyte} > 7) {
        getNextOutputByte($hr);
        $hr->{bitinoutputbyte} = 0;
    }

    if ($hr->{outputstuffed} && $hr->{onessent} >= 5) {
        $hr->{onessent} = 0;
        return 0;
    }
    my $nextdatabit = getBitInByte($hr->{currentoutputbyte},$hr->{bitinoutputbyte});
    if ($nextdatabit == 1) {
        ++$hr->{onessent};
    } else {
        $hr->{onessent} = 0;
    }
    ++$hr->{bitinoutputbyte};
    return $nextdatabit;
}

sub presentNextBit {
    my ($hr,$stuff) = @_;
    $hr->{txdat} = getNextStuffedBit($hr);
}

sub captureNextBit {
    my ($hr, $theirdat) = @_;
    if ($hr->{onesrcvd} >= 5) {
        if ($hr->{onesrcvd} == 5) {
            if ($theirdat == 0) {
                $hr->{onesrcvd} = 0;
            } else {
                $hr->{onesrcvd} = 6;
            }
            return;             # eat stuffed bit or frame delimiter/error bit
        }
        if ($hr->{onesrcvd} == 6) {
            if ($theirdat == 0) {
                $hr->{onesrcvd} = 0;
                if ($hr->{packetsync} == 1) {
                    if ($hr->{bytesininputpacket} > 0) {
                        printf("pru%d: RECEIVED PACKET '%s'\n",
                               $hr->{desiredclockxor},
                               join("",@{$hr->{input}}));
                    } else {
                        printf("pru%d: DISCARDING EMPTY PACKET\n",
                               $hr->{desiredclockxor});
                    }
                } else {
                    printf("pru%d: ACHIEVED PACKET SYNC\n",$hr->{desiredclockxor});
                    $hr->{packetsync} = 1;
                }
                $hr->{currentinputbyte} = 0;
                $hr->{bitininputbyte} = 0;
                $hr->{bytesininputpacket} = 0;
                $hr->{input} = [];
                return;
            }
            ++$hr->{onesrcvd};
       } 
        $hr->{packetsync} = 0;
        printf("pru%d: HANDLE PACKET FRAMING ERROR\n",$hr->{desiredclockxor});
        return;
    }

    if ($theirdat == 1) {
        $hr->{currentinputbyte} |= 1<<$hr->{bitininputbyte};
        ++$hr->{onesrcvd};
    } else {
        $hr->{onesrcvd} = 0;
    }
    if (++$hr->{bitininputbyte} > 7) {
        if ($hr->{packetsync}) {
            push @{$hr->{input}}, chr(0+$hr->{currentinputbyte});
            ++$hr->{bytesininputpacket};
        }
        $hr->{currentinputbyte} = 0;
        $hr->{bitininputbyte} = 0;
    }
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
    my $out = sprintf("s%d r%d d%d o%08b@%d[%s] i%08b@%d[%s]",
                      $hr->{state},
                      $hr->{txrdy},
                      $hr->{txdat},

                      $hr->{currentoutputbyte},
                      $hr->{bitinoutputbyte},
                      join("",@{$hr->{output}}),

                      $hr->{currentinputbyte},
                      $hr->{bitininputbyte},
                      join("",@{$hr->{input}})
        );
    return $out;
}

my $reportNum = 0;
sub reportPrus {
    printf("%3d %s %s\n", ++$reportNum,
           stringPru(\%pru0), 
           stringPru(\%pru1));
}

initPru(\%pru0, 0, chr(0), split(//,"h"), chr(0), chr(0xfc), chr(0x3f), split(//,"?"));

initPru(\%pru1, 1, chr(0), chr(0xff), split(//,"z!"), chr(0), chr(0), chr(0x7e), split(//,"norg"));


for (my $i = 0; $i < 1000; ++$i) {
    if (rand() < 0.5) {
        updatePru(\%pru0,\%pru1);
    } else {
        updatePru(\%pru1,\%pru0);
    }
}
