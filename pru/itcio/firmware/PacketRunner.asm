;;; -*- asm -*-
	
        .cdecls C,LIST
        %{
        #include "PacketRunner.h"
        #include "Buffers.h"
        #include "prux.h"
        %}

        .include "macros.asm"
        .include "structs.asm"
        
;;; Interclocking thread runner: Read and write packets
	.def PacketRunner
PacketRunner:
	clr CT.sTH.bFlags, CT.sTH.bFlags, PacketRunnerFlags.fPacketSync ; Init to not having sync
	ldi CT.bOutLen, 0              ; Init 0 says we're working on a 0 length packet
	ldi CT.bOutBCnt, 8             ; Init 8 says current byte all finished
	ldi CT.bInp1Cnt, 0             ; Init 0 says no run of 1s have been seen on input
	ldi CT.bOut1Cnt, 0             ; Init 0 says we haven't transmitted any run of 1s lately
        
        ;; FALL INTO getNextStuffedBit
	
getNextStuffedBit:  ;; Here to find next output bit to transmit
	qbge checkForBitStuffing, CT.bOutBCnt, 7  ; jump ahead if 7 >= bits sent in output byte
        ;; otherwise FALL INTO getNextOutputByte
	
getNextOutputByte:  ;; Here to fetch next output byte in packet if any
	qbge sendPacketDelimiter, CT.bOutLen, CT.bOutByte ; packet is done if outbyte >= outlen
	mov r14, CT.sTH.bID     ; arg1 to orbGetFrontPacketByte
        mov r15, CT.bOutByte    ; arg2 to orbGetFrontPacketByte
        jal r3.w2, orbGetFrontPacketByte ; go get next byte to send
        mov CT.bThisOut, r14             ; move output byte into position
	set CT.sTH.bFlags, CT.sTH.bFlags, PacketRunnerFlags.fOutputStuffed ; this byte SHOULD be bitstuffed
        add CT.bOutByte, CT.bOutByte, 1    ; increment bytes sent of this packet
        jmp startNewOutputByte

sendPacketDelimiter:   ;; time to send packet delimiter and discard finished packet
        ldi CT.bThisOut, 0x7e   ; set up packet delimiter
	clr CT.sTH.bFlags, CT.sTH.bFlags, PacketRunnerFlags.fOutputStuffed ; this byte should NOT be bitstuffed
	qbeq lookForNextPacket, CT.bOutLen, 0 ; jump ahead if current packet len is 0
	mov r14, CT.sTH.bID     ; arg1 to orbDropFrontPacket
        jal r3.w2, orbDropFrontPacket ; toss the packet we just finished sending

        ;; FALL INTO lookForNextPacket

lookForNextPacket: ;; here to set up next outbound packet if have sync and packets
        ldi CT.bOutByte, 0           ; No matter what we're on byte 0 now
	qbbc startNewOutputByte, CT.sTH.bFlags, PacketRunnerFlags.fPacketSync ; don't try for packets till we have sync
	mov r14, CT.sTH.bID          ; arg1 to orbFrontPacketLen
        jal r3.w2, orbFrontPacketLen ; next packetlen or 0 -> r14
        mov CT.bOutLen, r14          ; Save length of next packet or 0

startNewOutputByte:  ;; here to initialize once CT.bThisOut has new byte to send
        ldi CT.bOutBCnt, 0      ; no bits of bThisOut have been sent
	
        ;; FALL INTO checkForBitStuffing
	
checkForBitStuffing: ;; Here to maybe stuff output bits
	qbbc sendRealDataBit, CT.sTH.bFlags, PacketRunnerFlags.fOutputStuffed ; send real data if not stuffing this byte
	qble transmitZero, CT.bOut1Cnt, 5    ; but stuff a zero if 5 <= running 1s we've sent

        ;; FALL INTO sendRealDataBit
	
sendRealDataBit: ;; Here to send an actual (data or delimiter) bit
	add CT.bOut1Cnt, CT.bOut1Cnt, 1      ; Assume we're sending a 1
        qbbs transmitOne, CT.bThisOut, CT.bOutBCnt ; Go do that if we guessed right
	
        ;; FALL INTO transmitZero
	
transmitZero:        ;; Here to transmit 0 and clear our running 1s count
        ldi CT.bOut1Cnt, 0                   ; clear running 1s
	clr r30, r30, CT.bTXDATPin           ; present 0 on TXDAT
	jmp makeFallingEdge

transmitOne: ;; Here to transmit 1
	set r30, r30, CT.bTXDATPin           ; present 1 on TXDAT
        
        ;; FALL INTO makeFallingEdge
	
makeFallingEdge:  ;; Here to make a falling edge
        clr r30, r30, CT.bTXRDYPin      ; TXRDY falls
	add CT.bOutBCnt, CT.bOutBCnt, 1 ; And we have transmitted another bit
	saveResumePoint lowCheckClockPhases ; Set where to resume to and save this context
	
	;; FALL INTO clockLowLoop
	
clockLowLoop:  resumeNextThread          ; Context switch, without saving, to wait after falling edge
lowCheckClockPhases:
        .if ON_PRU == 0
          qbbc clockLowLoop, r31, CT.bRXRDYPin  ; PRU0 is MATCHER: if me 0, you 0, we're good
        .else                            ; ON_PRU == 1
	  qbbs clockLowLoop, r31, CT.bRXRDYPin  ; PRU1 is MISMATCHER: if me 0, you 1, we're good
        .endif  

	;; FALL INTO captureInputBit

captureInputBit:  ;; Here to sample RXDAT and handle it appropriately
	
	loadBit r0.b0, r31, CT.bRXDATPin ; Read RXDAT to r0.b0
	qblt storeRealInputBit, CT.bInp1Cnt, 5 ; Jump ahead if 5 < run of 1s we've read
        qbne moreThan5ones, CT.bInp1Cnt, 5     ; Jump ahead if 6 (or more?) 1s
        add CT.bInp1Cnt, CT.bInp1Cnt, 1        ; Assume it's another 1
	qbne makeRisingEdge, r0.b0, 0          ; If we guessed right, we're done, go make a rising edge
	ldi CT.bInp1Cnt, 0                     ; Otherwise clear the counter
        jmp makeRisingEdge                     ; And then we're done, go make a rising edge     

moreThan5ones: ;; Here to recognize frame delimiters and errors
	qbne frameError, CT.bInp1Cnt, 6        ; It's a framing error if not exactly six 1s
        add CT.bInp1Cnt, CT.bInp1Cnt, 1        ; Assume it's another 1
        qbne frameError, r0.b0, 0              ; Which is a framing error if so

	;; otherwise FALL INTO completeFrameDelimiter
	
completeFrameDelimiter:  ;; Here we have a (possibly misaligned) complete frame delimiter
        ldi CT.bInp1Cnt, 0      ; Reset input 1 count
        qbbc achievePacketSync, CT.sTH.bFlags, PacketRunnerFlags.fPacketSync ; If we didn't have sync, get it now
        
	;; otherwise FALL INTO checkExistingAlignment

checkExistingAlignment:  ;; Here we already have packet sync and are looking at a complete frame delimiter
        qbeq handleGoodPacketDelimiter, CT.bInpBCnt, 6 ; If at 7th bit, delimiter is aligned, go release full packet
	
	;; otherwise FALL INTO frameError

frameError:  ;; Here to deal with stuffing failures and misaligned delimiters while synced
	clr CT.sTH.bFlags, CT.sTH.bFlags, PacketRunnerFlags.fPacketSync ; Blow packet sync
	mov r14, CT.sTH.bID     ; arg1 is prudir
	mov r15, CT.bInpByte    ; arg2 is number of bytes written
        jal r3.w2, ipbReportFrameError ; Notify upstairs that we got problems down heah
        jmp resetAfterDelimiter

achievePacketSync: ;; Here to achieve packet sync when we didn't already have it
        set CT.sTH.bFlags, CT.sTH.bFlags, PacketRunnerFlags.fPacketSync ; Acheive packet sync

	;; FALL INTO resetAfterDelimiter

resetAfterDelimiter:  ;; Here to set up for new inbound packet
        ldi CT.bInpByte, 0         ; We are on byte 0
        ldi CT.bInpBCnt, 0         ; We are on bit 0 of byte 0
        ldi CT.bInpData, 0         ; And that byte is all 0s so far
        jmp makeRisingEdge         ; And then we're done with this input bit

handleGoodPacketDelimiter: ;; Here we finally have a finished packet!
        qbeq resetAfterDelimiter, CT.bInpByte, 0 ; But if it's zero-length, discard it!
        mov r14, CT.sTH.bID                      ; arg1 is prudir
        mov r15, CT.bInpByte                     ; arg2 is length
        jal r3.w2, ipbSendPacket                 ; Send the packet off to linux!  Foggin finally!
	jmp resetAfterDelimiter                  ; And set up for another

storeRealInputBit: ;; Here if not dealing with bitstuffed 0s, packet delimiters, or framing errors
        qbeq gotReal0, r0.b0, 0    ; No storing needed on zeros (because we cleared bInpData to start)
        set CT.bInpData, CT.bInpData, CT.bInpBCnt ; Otherwise set the bit we're on
        add CT.bInp1Cnt, CT.bInp1Cnt, 1           ; And increment the running 1s count
        jmp checkEndOfByte                        ; Go see if we've finished a byte

gotReal0:  ;; Here if we're seeing a real data bit 0
        ldi CT.bInp1Cnt, 0                        ; Clear running 1s count

        ;; FALL INTO checkEndOfByte

checkEndOfByte: ;; Here to increment and deal with end of byte processing
        add CT.bInpBCnt, CT.bInpBCnt, 1           ; Increment count of bits in byte
        qbge makeRisingEdge, CT.bInpBCnt, 7       ; Nothing more to do if 7 >= bits in byte
        qbbc makeRisingEdge, CT.sTH.bFlags, PacketRunnerFlags.fPacketSync ; Also nothing more to do if not synced
        mov r14, CT.sTH.bID     ; arg1 is prudir
        mov r15, CT.bInpByte    ; arg2 is what byte in the packet we just finished
	mov r16, CT.bInpData    ; arg3 is byte value to store
        jal r3.w2, ipbWriteByte ; go store this byte

        ;; FALL INTO setupForNextInputByte
        
setupForNextInputByte:  ;; Here to initialize for reading another byte
        add CT.bInpByte,  CT.bInpByte, 1 ; Move on to next byte
        ldi CT.bInpData, 0               ; Clear the byte data itself
        ldi CT.bInpBCnt, 0               ; And clear the bit in byte

        ;; FALL INTO makeRisingEdge
        
makeRisingEdge: ;; Here to make a rising clock edge
        set r30, r30, CT.bTXRDYPin        ; TXRDY rises
        saveResumePoint highCheckClockPhases ; Set where to resume to, and save this context
	
	;; FALL INTO clockHighLoop
clockHighLoop:  resumeNextThread          ; Context switch, without saving, to wait after rising edge
highCheckClockPhases:
        .if ON_PRU == 0 
          qbbs clockHighLoop, r31, CT.bRXRDYPin  ; PRU0 is MATCHER: if me 1, you 1, we're good
        .else                            ; ON_PRU == 1
	  qbbc clockHighLoop, r31, CT.bRXRDYPin  ; PRU1 is MISMATCHER: if me 1, you 0, we're good
        .endif  
        jmp getNextStuffedBit   ; And THEN DO IT ALL AGAIN
       
