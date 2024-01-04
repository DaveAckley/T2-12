import re
import PacketIO

class SerLoop:
    def __init__(self,serdev,configfile):
        self.pio = PacketIO.PacketIO(serdev)
        self.configFile = configfile
        self.tiles = []
        
        self.loadConfig()

    def loadConfig(self):
        idx = 0
        with open(self.configFile) as file:
            for line in file:
                if re.match('\s*#',line):
                    continue
                line = line.rstrip()
                args = line.split(maxsplit=2)
                if len(args) < 2:
                    raise ValueError(f"Bad config file {filename} line: {line}");
                (xpos, ypos, *rest) = args
                self.tiles.append((idx,xpos,ypos,rest))
                idx += 1
        tileCount = len(self.tiles)
        print(tileCount, "CONFIG\n","\n ".join([ str(x) for x in self.tiles]))

    def update(self):
        self.pio.update()
        count = 0
        while True:
            inpacket = self.pio.pendingPacket()
            if inpacket == None:
                break
            print("WHANDLED",inpacket)
            count = count + 1
        return count

    def close(self):
        self.pio.close()
        
