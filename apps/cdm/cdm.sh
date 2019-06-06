#!/bin/bash

cd /
while [ true ] ; do
    TERM=dumb /home/t2/T2-12/apps/cdm/cdm.pl
    echo cdm exited status $? -- RESTARTING
    sleep 2
done
