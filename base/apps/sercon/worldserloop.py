#!/usr/bin/python3

# WORLD SIMULATION PACKET RESPONDER

import PacketIO

pio = PacketIO.PacketIO('/dev/ttyO0')
print(pio)
raw = "I am a packet wrapped with tape\nHere is my null byte:\0\nHere's my escape\033!".encode()
print("ZONG",raw.decode('ascii'))
esc = pio.escape(raw)
print("BONB",esc)
print("HONG",pio.deescape(esc).decode('ascii'))
pio.close();



