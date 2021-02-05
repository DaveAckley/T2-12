#!/bin/bash

#OFFICIAL Mon Jan 21 09:45:23 2019:
#SEMIDEPRECATED Fri May  3 05:08:06 2019 mfms {1C1} --run --sf --sw 480 --sh 320 -a 0 --start-file /usr/lib/ulam/MFM/res/mfs/T2-12-13-start.mfs &
#MODRUN COOL NEW IF YOU HAVE /home/t2/MFMTMP:
#TRYING TO MAKE STANDARD AS E-SERIES T2s START APPEARING
#MOVING ON TO mfmt2
cd /
while [ true ] ; do
    echo Launching mfmt2
#    /home/t2/MFM/bin/mfmt2 -w /home/t2/MFM/res/mfmt2/wconfig.txt -z MFMT2-FAKE-MFZID -t
# Tue Jan 19 07:14:13 2021 We'll just let this keep dying until cdmss-a1-51f131.mfz is installed??
# Thu Jan 21 04:33:56 2021 Is -t killing the AER??
#    /home/t2/MFM/bin/mfmt2 -w /home/t2/MFM/res/mfmt2/wconfig.txt -z cdmss-a1-51f131.mfz -t/tmp -e/home/t2/physics/a1/code/.gen/bin/libcue.so
#    /home/t2/MFM/bin/mfmt2 -w /home/t2/MFM/res/mfmt2/wconfig.txt -z cdmss-a1-51f131.mfz -e/home/t2/physics/a1/code/.gen/bin/libcue.so
    # Just dish to mfm.pl to do config-specific launching
    /home/t2/T2-12/apps/mfm/mfm.pl
    echo mfmt2 exited status $? -- RESTARTING
#    echo Launching mfmt2
#    /home/t2/T2-12/apps/mfm/RUN_SDL /home/t2/MFM/bin/mfmt2 {{1H1}} --sw 480 --sh 320 --sf --start-file /home/t2/T2-12/apps/mfm/14stats.mfs --startsymbol SD -ep /home/t2/T2-12/apps/mfm/libcueSD.so --run -a 0 -n -wf 10 -e 10
#    echo mfmt2 exited status $? -- RESTARTING
    sleep 2
done



