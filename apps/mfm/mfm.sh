#!/bin/bash

#OFFICIAL Mon Jan 21 09:45:23 2019:
#SEMIDEPRECATED Fri May  3 05:08:06 2019 mfms {1C1} --run --sf --sw 480 --sh 320 -a 0 --start-file /usr/lib/ulam/MFM/res/mfs/T2-12-13-start.mfs &
#MODRUN COOL NEW IF YOU HAVE /home/t2/MFMTMP:
#TRYING TO MAKE STANDARD AS E-SERIES T2s START APPEARING
/home/t2/GITHUB/MFM/bin/mfms {1H1} --run -n -a 0 --sw 480 --sh 320 --sf -ep /home/t2/MFMTMP/.gen/bin/libcue.so --start-file /home/t2/MFMTMP/10.mfs
export MFM_PID=$!
echo "Started $MFM_PID"
sleep 1
# Currently have no idea why mfms hangs until
# it gets a (particular?) signal.  Guessing it's
# about the lack of a tty..
kill -TSTP %1
kill -CONT %1
sleep 1
trap "kill -9 $MFM_PID" SIGINT SIGTERM
wait


