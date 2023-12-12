#!/usr/bin/python3

## GET ACCESS TO OUR OWN PRIVATE SERIAL
import sys
sys.path.append('/home/t2/T2-12/base/files/misc/root/.local/lib/python3.7/site-packages/')
                           
import time
import serial

ser = serial.Serial('/dev/ttyO0', 115200, timeout=1)
print(ser.portstr)
ser.write("hellpO\n".encode('ascii'))
while (True):
    avail = ser.inWaiting()
    if (avail > 0):
        data = ser.read(avail).decode('ascii')
        print ("GOT",data)
    time.sleep(0.1)

ser.close()


