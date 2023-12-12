#!/usr/bin/python3

# T2 TILE PACKET RESPONDER


## GET ACCESS TO OUR OWN PRIVATE SERIAL
import sys
sys.path.append('/home/t2/T2-12/base/files/misc/root/.local/lib/python3.7/site-packages/')
                           
import time
import serial

import re

class PacketIO:
    def __init__(self,serdev):
        self.serdev = serdev
        self.ser = serial.Serial(serdev, 115200, timeout=0, write_timeout=0)
        self.bytesin = bytearray()
        self.bytesout = bytearray()
        self.pendingin = []

    def close(self):
        self.ser.close();
        self.ser = None

    def update(self):
        read = self.updateRead()
        wrote = self.updateWrite()
        return read+wrote

    def updateRead(self):
        bytes = self.ser.read(256)
        if (bytes > 0):
            self.acceptBytes(bytes)
        return bytes

    def updateWrite(self):
        wrote = 0
        if len(self.bytesout) > 0:
            wrote = self.ser.write(self.bytesout)
            if wrote > 0:
                self.bytesout = self.bytesout[wrote:]
        return wrote

    def writePacket(self,packet):
        self.bytesout += self.escape(packet)

    def acceptBytes(self,bytes):
        self.bytesin += bytearray(bytes)

        while True:
            pos = self.bytesin.find(b'\n')
            if pos < 0:
                break
            packet = self.bytesin[:pos]   # not including \n
            self.bytesin[pos+1:]          # also not including \n
            packet = self.deescape(packet)
            self.pendingin.append(packet)

    def escape(self,packet):
        def escapeByte(byte):
            if byte == b'\033':
                return b'\033e'
            if byte == b'\n':
                return b'\033n'
            return byte
        esc =re.sub(b'([\033\n])', lambda m: escapeByte(m.group(1)), packet)
        return esc

    def deescape(self,packet):
        def deescapeByte(byte):
            if byte == b'e':
                return b'\033'
            if byte == b'n':
                return b'\n'
            raise ValueError(f"Invalid escape byte {byte}")
        des =re.sub(b'(\033(.))', lambda m: deescapeByte(m.group(2)), packet)
        return des

    def deescapeOLD(self,packet):
        done = b''
        remaining = packet
        while True:
            print("god",done,remaining)
            idx = remaining.find(b'\033')
            if idx < 0:
                break
            done += remaining[:idx] # not include ESC
            escape = remaining[idx+1:idx+2] # byte after ESC if any
            remaining = remaining[idx+2:]
            if escape == b'e':
                done += bytearray(b'\033') # escaped ESC
            elif escape == b'n':
                done += bytearray(b'\n') # escaped \n
            else:
                raise ValueError(f"Illegal escape '{escape}'")
        done += remaining       # ESC free tail
        return done

    

pio = PacketIO('/dev/ttyO0')
print(pio)
raw = 'I am a packet wrapped with tape\nHere is my null byte:\0\nHere\'s my escape\033!'.encode()
print("ZONG",raw.decode('ascii'))
esc = pio.escape(raw)
print("BONB",esc)
print("HONG",pio.deescape(esc).decode('ascii'))
pio.close();



