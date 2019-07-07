#!/bin/bash

prognames=(cdm.sh cdm.pl mfmt2)
for i in "${prognames[@]}"
do
    pid=`ps -o pid= -C $i` &&
        echo -n Trying to kill $i $pid &&
        kill $pid &&
        echo " done"
done
echo -n "wait for it: "
sleep 3
lsmod | grep ^itc_pkt

         
