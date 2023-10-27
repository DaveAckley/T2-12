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
        print("ACCBYT",self.bytesin)
        while True:
            pos = self.bytesin.find(b'\n')
            if pos < 0:
                break
            packet = self.bytesin[:pos]   # not including \n
            self.bytesin[pos+1:]          # also not including \n
            packet = self.deescape(packet)
            print("ACCBYTFOUND",packet)
            self.pendingin.append(packet)

    def escape(self,packet):
        """ Escape ESC and \n bytes (as \033e and \033n) in packet """
        def escapeByte(byte):
            if byte == b'\033':
                return b'\033e'
            if byte == b'\n':
                return b'\033n'
            return byte
        esc =re.sub(b'([\033\n])', lambda m: escapeByte(m.group(1)), packet)
        return esc

    def deescape(self,packet):
        """ Deescape previously escape'd bytes in packet """
        def deescapeByte(byte):
            if byte == b'e':
                return b'\033'
            if byte == b'n':
                return b'\n'
            raise ValueError(f"Invalid escape byte {byte}")
        des =re.sub(b'(\033(.))', lambda m: deescapeByte(m.group(2)), packet)
        return des
