#!/usr/bin/python3

# WORLD SIMULATION PACKET RESPONDER

import PacketIO
import SerLoop
from time import sleep

import sys
import re

if len(sys.argv) != 2:
    raise ValueError("Need exactly one argument (config file path)");

configfile = sys.argv[1]

sl = SerLoop.SerLoop('/dev/ttyUSB0',configfile)

## COUNT THE LOOP

loopLen = None
if True:
    tries = 0
    nonce = sl.pio.randomAlphaNum(8)
    p = sl.pio.makePacket(-1,b'LOOPCOUNT/',nonce)
    sl.pio.writePacket(p)
    while tries < 250:
        tries += 1
        sl.pio.update()
        inpacket = sl.pio.pendingPacket()
        if inpacket == None:
            sleep(.1)
            continue
        m = sl.pio.matchPacket(b'(.)LOOPCOUNT/'+nonce,inpacket) 
        if m:
            count = sl.pio.getHops(inpacket)
            loopLen = -count-1
            break
        print("DISCARDING UNMATCHED: ",inpacket)

if loopLen == None:
    print("LOOP COUNTING FAILED")
    exit(1)

print("LOOP LENGTH IS",loopLen)
            
count = 0
while True:
    sl.update();
    sleep(.1)
    count += 1
    if count % 100 == 0:
        print("SENDDDD")
        sl.pio.writePacket(b'-\xff')

sl.close();



