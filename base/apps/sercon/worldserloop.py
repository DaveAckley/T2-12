#!/usr/bin/python3

# WORLD SIMULATION PACKET RESPONDER

import PacketIO
from time import sleep

pio = PacketIO.PacketIO('/dev/ttyUSB0')
print(pio)
while True:
    pio.update()
    while True:
        inpacket = pio.pendingPacket()
        if inpacket == None:
            break
        print("WHANDLED",inpacket)
    sleep(.1)
pio.close();



