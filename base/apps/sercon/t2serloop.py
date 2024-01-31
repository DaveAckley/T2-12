#!/usr/bin/python3

# T2 TILE PACKET RESPONDER

import PacketIO
from time import sleep
#from Utils import *

import tomlikey as toml
import hashlib

import Config
import Spine

confdir = "/mnt/T2TMP"
configfile = confdir+"/world.toml"

tagsfile = confdir+"/tags.dat"
inputfile = confdir+"/input.dat"
outputfile = confdir+"/output.dat"

config = Config.Config("t2cfg",configfile)
print("OHCNSOIKFG",config)

pio = PacketIO.PacketIO('/dev/ttyO0')
print("HAWO",pio)
#raw = b"I'm a little packet (\xf1) made of tape\nHere is my null byte:\0\nHere's my escape\033!"
#print("ZBNG",raw)
#esc = pio.escape(raw)
#print("BONB",esc)
#print("HONG",pio.deescape(esc))

def performPacketIO(packet):
    ####BEGIN DISGUSTING HARDCODE HACK TO PERFORM CROSSOVER ROUTING
    if len(packet)==13:
        # ASSUMING ALL TERMINALS ARE ASSIGNED TO ONE TILE
        # MLR 0, MRR 1, SLFL 2, SRFL 3, so
        # mlr 5 6, mrr 7 8, slfl 9 10, srfl 11 12
        # want slfl -> mrr and srfl -> mlr
        packet[8] = packet[10] # slfl -> mrr
        packet[6] = packet[12] # srfl -> mlr
        print("ROUTONGO",packet)
    ####END DISGUSTING HARDCODE HACK TO PERFORM CROSSOVER ROUTING

def writeTagsDatFile(terms):
    ba = bytearray()
    for tag in terms['_indices_']:
        term = terms.get(tag)
        if term == None:
            print("MISGTRM",tag)
            continue
        type = term['type']
        if type == 'sensor':
            code = b'>'
        elif type == 'motor':
            code = b'<'
        else:
            code = b'?'
        ba += code+tag.encode()+b'\n'

    with open(tagsfile,"wb") as file:
        file.write(ba)

def recvFullConfig(fbytes):
    with open(configfile,"wb") as file:
        file.write(fbytes)
    config.reset()
    config.load()
    terms = config.getInitializedSection('term',{})
    Spine.IndexTerminals(terms)
    writeTagsDatFile(terms)

def checkConfigChecksum(p):
    hit = False
    try:
        with open(configfile,"rb") as file:
            raw = file.read()
        h = hashlib.sha256()
        h.update(raw)
        fcs = h.digest()
        csbytes = p[5:]
        hit = fcs == csbytes
    except Exception as e:
        print("NOCSFILE",e)
    if not hit:
        p[4] += 1
        print("CNFCHKMIS")
    

def handleBroadcast(p):
    if len(p) < 6:
        print("SHORTVOARD",p)
    elif p[1] != ord(b'C'):     # Config packet only bcast so far
        print("UNREGBORAD",p)
    else:
        if p[2] < 125:
            p[2] += 1         # increment broadcast hops
        if p[3] == ord(b'f'): # 'f'ull file attached
            recvFullConfig(p[4:])
        elif p[3] == ord(b's'): # file check's'um attached
            checkConfigChecksum(p)
        else:
            print("UNREGBRCP",p)

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
        elif hops == 126:   # Broadcast!
            handleBroadcast(inpacket)  # Modifies inpacket in place!
            print("FWD",inpacket)
            pio.writePacket(inpacket)
        elif hops == 0:
            if (len(inpacket) >= 5 and  # W pkt reqd: hops,'W',dest,nonce,type
                inpacket[1] == ord(b'W') and
                inpacket[4] == ord(b'I')):
                print("GOT WI",inpacket)
                performPacketIO(inpacket)  # Modifies inpacket in place!
                pio.setHops(inpacket,hops-1)
                inpacket[4] = ord(b'O')
                print("FWD",inpacket)
                pio.writePacket(inpacket)
            else:
                print("HANDLE LOCAL!",inpacket)
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



