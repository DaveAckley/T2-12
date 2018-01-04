#!/bin/bash

# Thu Jan  4 01:46:54 2018 The struggle to fix the touchscreen flares
# up once again, but again, so far, with no satisfying resolution
export SDL_MOUSEDRV=TSLIB
export SDL_MOUSEDEV=/dev/input/touchscreen
export SDL_FBDEV=/dev/fb0
export SDL_VIDEODRIVER=fbcon

mfms {1C1} --run --sf --sw 480 --sh 320 -a 0 --start-file /usr/lib/ulam/MFM/res/mfs/T2-12-13-start.mfs &
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


