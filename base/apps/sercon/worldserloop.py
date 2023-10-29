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

count = 0
while True:
    sl.update();
    sleep(.1)
    count += 1
    if count % 100 == 0:
        print("SENDDDD")
        sl.pio.writePacket(b'-\xff')

sl.close();



