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
        print("HANDLED",inpacket)
    count += 1
    if count % 100 == 0:
        print("SENDOOO")
        bcount = str(count).encode()
        pio.writePacket(bcount+b'HEWO big packet \n\n\n more more want serial to not be able to take the whole thing in one buffer or something like that you know test test zongHEWO big packet \n\n\n more more want serial to not be able to take the whole thing in one buffer or something like that you know test test zongHEWO big packet \n\n\n more more want serial to not be able to take the whole thing in one buffer or something like that you know test test zongHEWO big packet \n\n\n more more want serial to not be able to take the whole thing in one buffer or something like that you know test test zong')
    sleep(.1)

pio.close();



