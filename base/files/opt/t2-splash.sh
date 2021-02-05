#!/bin/bash

# Wait for /dev/fb0

COUNTER=0
while [ ! -c /dev/fb0 ]; do
    sleep 1
    let COUNTER=COUNTER+1
    if [ $COUNTER -gt 50 ]; then
	logger T2 CANNOT FIND /dev/fb0
	exit 2
    fi
done

# Run splash screen
export SDL_NOMOUSE=1
/opt/scripts/t2/sdlsplash /opt/scripts/t2/t2-splash.png

exit 0
