#!/usr/bin/python3

# T2 TILE PACKET RESPONDER

import PacketIO
from time import sleep

pio = PacketIO.PacketIO('/dev/ttyO0')
print(pio)
raw = "I am a packet wrapped with tape\nHere is my null byte:\0\nHere's my escape\033!".encode()
print("ZONG",raw.decode('ascii'))
esc = pio.escape(raw)
print("BONB",esc)
print("HONG",pio.deescape(esc).decode('ascii'))

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
        pio.writePacket(b'HEWO big packet \n\n\n more more want serial to not be able to take the whole thing in one buffer or something like that you know test test zongHEWO big packet \n\n\n more more want serial to not be able to take the whole thing in one buffer or something like that you know test test zongHEWO big packet \n\n\n more more want serial to not be able to take the whole thing in one buffer or something like that you know test test zongHEWO big packet \n\n\n more more want serial to not be able to take the whole thing in one buffer or something like that you know test test zong')
    sleep(.1)

pio.close();



