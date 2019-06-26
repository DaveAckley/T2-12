#!/bin/bash

#OFFICIAL Mon Jan 21 09:45:23 2019:
#SEMIDEPRECATED Fri May  3 05:08:06 2019 mfms {1C1} --run --sf --sw 480 --sh 320 -a 0 --start-file /usr/lib/ulam/MFM/res/mfs/T2-12-13-start.mfs &
#MODRUN COOL NEW IF YOU HAVE /home/t2/MFMTMP:
#TRYING TO MAKE STANDARD AS E-SERIES T2s START APPEARING
#/home/t2/GITHUB/MFM/bin/mfms {1H1} --run -n -a 0 --sw 480 --sh 320 --sf -ep /home/t2/MFMTMP/.gen/bin/libcue.so --start-file /home/t2/MFMTMP/10.mfs
#MOVING ON TO mfmt2
/home/t2/T2-12/apps/mfm/RUN_SDL /home/t2/GITHUB/MFM/bin/mfmt2 {1H1} --sw 480 --sh 320 --sf --start-file /home/t2/T2-12/apps/mfm/11.mfs -cp /home/t2/T2-12/apps/mfm/11.mfs -ep /home/t2/MFMTMP/.gen/bin/libcue.so --run -a 0 -n



