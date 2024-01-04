## GET ACCESS TO OUR OWN PRIVATE SERIAL
import sys
sys.path.append('/home/t2/T2-12/base/files/misc/root/.local/lib/python3.7/site-packages/')

import time
import serial
import re
import random
from string import ascii_letters, digits

from Utils import *

from binascii import crc_hqx

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
        nbytes = len(bytes)
        if (nbytes > 0):
            self.acceptBytes(bytes)
        return nbytes

    def updateWrite(self):
        wrote = 0
        if len(self.bytesout) > 0:
            wrote = self.ser.write(self.bytesout)
            if wrote > 0:
                self.bytesout = self.bytesout[wrote:]
        return wrote

    def writePacket(self,packet):
        self.bytesout += self.escape(packet)
        self.bytesout += b'\n'

    def acceptBytes(self,bytes):
        self.bytesin += bytearray(bytes)
        #print("ACCBYT",self.bytesin)
        while True:
            pos = self.bytesin.find(b'\n')
            if pos < 0:
                break
            packet = self.bytesin[:pos]         # not including \n
            self.bytesin = self.bytesin[pos+1:] # also not including \n
            try:
                packet = self.deescape(packet) # exception on bad pkt/chksum
                print("ACCBYTFND",packet)
                self.pendingin.append(packet)
            except ValueError as v:
                print("Packet discarded:",v)

    def pendingPacket(self):
        if len(self.pendingin) == 0:
            return None
        packet = self.pendingin[0]
        self.pendingin = self.pendingin[1:]
        return packet

    def escape(self,packet):
        """
        Append a two-byte checksum, then
        escape ESC and \n bytes (as \033e and \033n) 
        in the resulting bytes.  
        """

        packet += self.crcBytes(packet)
        
        def escapeByte(byte):
            if byte == b'\033':
                return b'\033e'
            if byte == b'\n':
                return b'\033n'
            return byte
        esc =re.sub(b'([\033\n])', lambda m: escapeByte(m.group(1)), packet)
        return esc

    def deescape(self,packet):
        """ 
        Deescape previously escape'd bytes in packet,
        then check and strip the checksum of the result.
        """
        def deescapeByte(byte):
            if byte == b'e':
                return b'\033'
            if byte == b'n':
                return b'\n'
            raise ValueError(f"Invalid escape byte {byte}")
        des =re.sub(b'(\033(.))', lambda m: deescapeByte(m.group(2)), packet)

        if len(des) < 2:
            raise ValueError(f"Packet too short for checksum")
        if crc_hqx(des,0) != 0:
            raise ValueError(f"Checksum failure in {des}")
        return bytearray(des[:-2])

    def crcBytes(self,bytes):
        crc = crc_hqx(bytes,0)
        return b"%c%c" % ((crc>>8)&0xff,crc&0xff)

    def getHops(self,packet):
        if len(packet) == 0:
            raise ValueError(f"Packet too short for hops")
        return signedByteToInt(packet[0])

    def setHops(self,packet,hops):
        if len(packet) == 0:
            raise ValueError(f"Packet too short for hops")
        packet[0] = intToSignedByte(hops)

    def makePacket(self,hops,*args):
        packet = bytearray(1)
        self.setHops(packet,hops)
        for a in args:
            packet += a
        return packet

    def matchPacket(self,pattern,packet):
        return re.search(pattern,packet)

    alphanum = ascii_letters + digits
    def randomAlphaNum(self,bytecount):
        return self.randomBytesFromString(PacketIO.alphanum,bytecount)

    def randomBytesFromString(self,string,bytecount):
        return b''.join([bytes(random.choice(string),'utf-8') for i in range(bytecount)])
        
