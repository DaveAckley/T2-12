#!/bin/bash

DIR=/opt/scripts/t2
cd /
while [ true ] ; do
    TERM=dumb $DIR/cdm/cdm.pl
    echo cdm exited status $? -- RESTARTING
    sleep 2
done
