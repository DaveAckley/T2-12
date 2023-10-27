#!/bin/bash
#export MYPYSERIAL=/home/t2/T2-12/base/files/misc/root/.local/lib/python3.7/site-packages/
#export PYTHONPATH=$PYTHONPATH:$MYPYSERIAL

while [ 1 ] ; do
    date '+STARTING WORLD SERLOOP %Y-%m-%d %H:%M:%S'
    ./worldserloop.py
    sleep 1
done
