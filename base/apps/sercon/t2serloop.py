#!/usr/bin/env python

# T2 TILE PACKET RESPONDER
import sys
argc = len(sys.argv)
serdev = '/dev/ttyO0'
if argc > 1:
    serdev = sys.argv[1]
if argc > 2:
    print("Usage:",sys.argv[0],'OPTSERDEV')
print("SERDEV:",serdev)

import PacketIO
from time import sleep
#from Utils import *

import pathlib

import tomlikey as toml
import hashlib

import Config
import Spine

confdir = "/mnt/T2TMP"
tomlfile = confdir+"/world.toml"

tagsfile = confdir+"/tags.dat"
inputfile = confdir+"/input.dat"
outputfile = confdir+"/output.dat"
configfile = confdir+"/config.dat"

tomlData = None

def performPacketIO(packet):
    packetlen = len(packet)
    with open(inputfile,"wb") as file:
        file.write(packet[5:])
    try:
        newpacket = b''
        with open(outputfile,"rb") as file:
            newpacket = file.read()
        #print("PPIONP",newpacket,packet)
    except Exception as e:
        print("NO MOTOR:",e)
        return
    if len(newpacket)+5 != len(packet): # discard mismatches
        print("PPIOBLENDISCARD",len(newpacket),packetlen,newpacket,packet)
        newpacket = bytearray(packet)   # just reship old unmodified?
    # collect matching motor values from newpacket
    if tomlData == None:
        return
    terms = tomlData.getRequiredSection('term')
    types = terms['_types_']
    
    for i in range(0,len(newpacket)-1,2):
        if i+6 >= packetlen:    # if new terms, might not fit in old packet
            print("GOZIZEBO",i+6,packetlen)
            continue
        (idx,val) = (newpacket[i],newpacket[i+1])
        if idx >= len(types):    # if new terms, might not fit in old packet
            print("GOTIPESBO",idx,len(types))
            continue

        if idx != packet[i+5] or types[idx] != 'motor':
            #if types[idx] != 'sensor':
            #    print("GOMOTRBO",idx,packet[i+5],types[idx])
            continue
        #print("GOGOTS",i+6,packet[i+6],val,types[idx])
        packet[i+6] = val
        
def writeTagsDatFile(terms):
    ba = bytearray()
    for (tag,type) in zip(terms['_indices_'],terms['_types_']):
        if type == 'sensor':
            code = b'>'
        elif type == 'motor':
            code = b'<'
        elif type == 'control':
            code = b'!'
        else:
            code = b'?'
        ba += code+tag.encode()+b'\n'

    with open(tagsfile,"wb") as file:
        file.write(ba)

def writeConfigDatFile(config):
    ba = bytearray()
    print("WEIFOVNFOG",config)
    for (key,val) in config.items():
        if isinstance(val,str):
            ba += key.encode()+b':'+val.encode()+b'\n'
    with open(configfile,"wb") as file:
        file.write(ba)

def needTags():
    tf = pathlib.Path(tagsfile)
    wf = pathlib.Path(tomlfile)
    if not tf.exists() or not wf.exists():
        return True
    # Also need tags if tags file older than world file
    return tf.stat().st_mtime_ns <= wf.stat().st_mtime_ns

def recvFullTomlData(fbytes):
    with open(tomlfile,"wb") as file:
        file.write(fbytes)
    indexTomlData()

def indexTomlData():
    global tomlData
    if not tomlData:
        tomlData = Config.Config("t2cfg",tomlfile)
    tomlData.reset()
    tomlData.load()

    # configSect = config.getOptionalSection("config")
    # secsPerStep = 5
    # if configSect != None:
    #     cadence = configSect.get("cadence")
    #     if cadence != None:
    #         secsPerStep = int(cadence)
    # print("CADENCE:",secsPerStep)

    terms = tomlData.getInitializedSection('term',{})
    Spine.IndexTerminals(terms)
    writeTagsDatFile(terms)
    config = tomlData.getInitializedSection('config',{})
    writeConfigDatFile(config)

def checkTomlDataChecksum(p):
    hit = False
    print("TRY checkTomlDataChecksum")
    try:
        with open(tomlfile,"rb") as file:
            raw = file.read()
        h = hashlib.sha256()
        h.update(raw)
        fcs = h.digest()
        csbytes = p[5:]
        hit = fcs == csbytes
    except Exception as e:
        print("NOCSFILE",e)
    if not hit or needTags():
        p[4] += 1
        print("CNFCHKMIS")
    else:
        print("CNFCHKHIT")
        

def handleBroadcast(p):
    if len(p) < 6:
        print("SHORTVOARD",p)
    elif p[1] != ord(b'C'):     # Config packet only bcast so far
        print("UNREGBORAD",p)
    else:
        if p[2] < 125:
            p[2] += 1         # increment broadcast hops
        if p[3] == ord(b'f'): # 'f'ull file attached
            recvFullTomlData(p[4:])
        elif p[3] == ord(b's'): # file check's'um attached
            checkTomlDataChecksum(p)
        else:
            print("UNREGBRCP",p)

if pathlib.Path(tomlfile).is_file(): # preload existing tomldata
    indexTomlData()
    print("OHCNSOIKFG",tomlData)
    

pio = PacketIO.PacketIO(serdev)
print("HAWO",pio)
#raw = b"I'm a little packet (\xf1) made of tape\nHere is my null byte:\0\nHere's my escape\033!"
#print("ZBNG",raw)
#esc = pio.escape(raw)
#print("BONB",esc)
#print("HONG",pio.deescape(esc))

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
            #print("FWD",inpacket)
            pio.writePacket(inpacket)
        elif hops == 0:
            if (len(inpacket) >= 5 and  # W pkt reqd: hops,'W',dest,nonce,type
                inpacket[1] == ord(b'W') and
                inpacket[4] == ord(b'I')):
                #print("GOT WI",inpacket)
                performPacketIO(inpacket)  # Modifies inpacket in place!
                pio.setHops(inpacket,hops-1)
                inpacket[4] = ord(b'O')
                #print("FWD",inpacket)
                pio.writePacket(inpacket)
            else:
                print("HANDLE LOCAL!",inpacket)
        else:                   # cmd or reply heading downstream
            pio.setHops(inpacket,hops-1)
            #print("FWD",inpacket)
            pio.writePacket(inpacket)
    count += 1
    if count % 1000 == 0:
        stats = pio.getStats()
        print("LOOPTRAF",count,stats)
    if count == 100:
        print("SENDOOO")
        bcount = str(count).encode()
        pio.writePacket(bcount+b'HEWO big packet \n\n\n more more want serial to not be able to take the whole thing in one buffer or something like that you know test test zongHEWO big packet \n\n\n more more want serial to not be able to take the whole thing in one buffer or something like that you know test test zongHEWO big packet \n\n\n more more want serial to not be able to take the whole thing in one buffer or something like that you know test test zongHEWO big packet \n\n\n more more want serial to not be able to take the whole thing in one buffer or something like that you know test test zong')
    sleep(.1)

pio.close();



