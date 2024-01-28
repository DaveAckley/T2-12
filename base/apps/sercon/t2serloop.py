#!/usr/bin/python3

# T2 TILE PACKET RESPONDER

import PacketIO
from time import sleep

pio = PacketIO.PacketIO('/dev/ttyO0')
print(pio)
raw = b"I'm a little packet (\xf1) made of tape\nHere is my null byte:\0\nHere's my escape\033!"
print("ZBNG",raw)
esc = pio.escape(raw)
print("BONB",esc)
print("HONG",pio.deescape(esc))

count = 0
while True:
    pio.update()
    while True:
        inpacket = pio.pendingPacket()
        if inpacket == None:
            break
        #print("GOT",inpacket)
        if len(inpacket) < 2:
            break
        hops = pio.getHops(inpacket)
        if hops <= -126 or hops >= 127:
            print("TOST",inpacket) # discard underflows and reserved crap
        elif hops == 0:
            if (len(inpacket) >= 6 and
                inpacket[1] == ord(b'W') and
                inpacket[4] == ord(b'I')):
                print("GOT W",inpacket)
                pio.setHops(inpacket,hops-1)
                inpacket[4] = ord(b'O')
                print("FWD",inpacket)
                pio.writePacket(inpacket)
            else:
                print("HANDLE LOCAL!",inpacket)
        elif hops == 126:
            print("HANDLE BCAST!",inpacket)
        else:                   # cmd or reply heading downstream
            pio.setHops(inpacket,hops-1)
            print("FWD",inpacket)
            pio.writePacket(inpacket)
    count += 1
    if count == 100:
        print("SENDOOO")
        bcount = str(count).encode()
        pio.writePacket(bcount+b'HEWO big packet \n\n\n more more want serial to not be able to take the whole thing in one buffer or something like that you know test test zongHEWO big packet \n\n\n more more want serial to not be able to take the whole thing in one buffer or something like that you know test test zongHEWO big packet \n\n\n more more want serial to not be able to take the whole thing in one buffer or something like that you know test test zongHEWO big packet \n\n\n more more want serial to not be able to take the whole thing in one buffer or something like that you know test test zong')
    sleep(.1)

pio.close();



