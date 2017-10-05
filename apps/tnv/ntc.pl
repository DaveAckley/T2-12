#!/usr/bin/perl -Tw

# Vishay NTC 3rd order polynomial temperature-from-resistance formula
#
#   Rt = R25 * exp(A + B/T + C/T**2 + D/T**3)
#
#   T = 1 / (A1 + B1*ln(Rt/R25) + C1*ln(Rt/R25)**2 + D1*ln(Rt/R25)**3
#
# where Rt is in Ohms and T is in Kelvins (deg C + 273.15)

# The T2-12 tile (as of T2-12-15 / 201709091637 anyway), is using a
# 10K ohm 2% tolerance NTC, Vishay part number NTCS0805E3103GMT.
#
# Constants for that part, taken from the spreadsheet downloaded from
# http://www.vishay.com/doc?29100 on 20170910 (which was linked from
# http://www.vishay.com/thermistors/curve-computation-list), are:
my ($A,$B,$C,$D) =
    (-13.4088568, 4547.9615, -176965.92, 3861154);
my ($A1,$B1,$C1,$D1) =
    (0.003354016, 0.0002864517, 3.252255E-06, 4.594501E-08);
my $R25 = 10000.0;

sub computeRTfromTC {
    my $TC = shift;
    my $TK = $TC + 273.15;
    my $Rt = $R25 * exp($A + $B / $TK + $C / ($TK**2) + $D / ($TK**3));
    return $Rt;
}

sub computeTCfromRT {
    my $Rt = shift;
    my $TK =
        1.0 / ($A1 +
               $B1 * log($Rt/$R25) +
               $C1 * log($Rt/$R25)**2 +
               $D1 * log($Rt/$R25)**3);
    my $TC = $TK - 273.15;
    return $TC;
}

sub generateTCtoRTTable {
    for (my $T = -55; $T <= 150; $T += 1) {
        my $Rt = computeRTfromTC($T);
        my $TC = computeTCfromRT($Rt);
        printf("%5.1f  %10.5f  %10.5f\n",$T,$Rt,$TC);
    }

}

# We currently have voltage dividers like these:
#
#                            Rt
#             10K 0.1%      +---+
#  1.8V o------/\/\/----o---|NTC|----o GNDA
#                       |   +---+    |
#                       |            |
#                    V1 o... AINx ...o
#
# with AINx producing 0..4095 for 0V..1.8V
#
# Which gives us:
#
#  V1 = 1.8 * Rt / (Rt + 10000)
#
#  count4K = 4095 * V1 / 1.8
#
#  count4K = 4095 * 1.8 * (Rt / (Rt + 10000)) / 1.8
#
#  count4K = 4095 * Rt / (Rt + 10000)
#
#  count4K/4095 =  Rt / (Rt + 10000)
#
#  count4K/4095 =  1 / (1 + 10000/Rt)  given Rt > 0
#
#  4095/count4K =  (1 + 10000/Rt)  given count4K > 0
#
#  4095/count4K - 1 =  10000/Rt    given count4k < 4095
#
# 1 / (4095/count4K - 1) =  Rt/10000
#
# 10000 / (4095/count4K - 1) =  Rt
#
# Rt = 10000 / (4095/count4K - 1)
#
sub computeRTfrom4K {
    my $count4K = shift;
    die "Bad count $count4K" if $count4K <= 0 or $count4K >= 4095;
    my $V1 = 1.8 * $count4K / 4095.0;
    my $Rt = $R25 / (4095.0/$count4K - 1.0);
    return $Rt;
}

sub generate4KtoTCTable {
    print <<EOM;
#include <stdint.h>

/* map from 12 bit ADC count -> 1024 * centigrade.
   adcToTc1K[0] and adcToTc1K[4095] are illegal values
   producing INT32_MAX.
 */
const int32_t adcToTc1K[4096] = {
  INT32_MAX,   // [0], C = oh sure, F = 9/5 + sure
EOM
    for (my $count = 1; $count < 4095; $count += 1) {
        my $Rt = computeRTfrom4K($count);
        my $TC = computeTCfromRT($Rt);
        my $TC1K = int(1024*$TC);
        my $TF = 9.0/5.0 * $TC + 32;
        printf("  %d,      // [%d], C = %7.2f, F = %7.2f\n",
               $TC1K,$count,$TC,$TF);
    }
    print <<EOM;
  INT32_MAX     // [4095], C = -yeah right, F = -uh huh
}; // end adcToTc1K

bool validCount(unsigned count) {
  return count > 0 && count < 4095;
}

int getCentigradeFromCount(unsigned count) {
  if (!validCount(count)) return INT32_MAX;
  return adcToTc1K[count] >> 10;
}

float getFloatCentigradeFromCount(unsigned count) {
  if (!validCount(count)) return INT32_MAX;
  return adcToTc1K[count]/1024.0;
}

float getFloatFarenheitFromCount(unsigned count) {
  if (!validCount(count)) return INT32_MAX;
  return getFloatCentigradeFromCount(count) * 9 / 5 + 32;
}

int getFarenheitFromCount(unsigned count) {
  if (!validCount(count)) return INT32_MAX;
  return (int) (getFloatFarenheitFromCount(count) + 0.5);
}

EOM
}

my $arg = ((shift @ARGV) || "table");
if ($arg eq "header" ) {
    print <<EOM;
#ifndef T2_ADC_NTC_CVT_H
#define T2_ADC_NTC_CVT_H

int getCentigradeFromCount(unsigned count) ;

float getFloatCentigradeFromCount(unsigned count) ;

float getFloatFarenheitFromCount(unsigned count) ;

int getFarenheitFromCount(unsigned count) ;

#endif /* T2_ADC_NTC_CVT_H */
EOM
} elsif ($arg eq "table") {
    generate4KtoTCTable();
} else {
    die "Usage: $0 [header]\n";
}

