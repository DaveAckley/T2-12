;;; -*- asm -*-
	
        .cdecls C,LIST
        %{
        #include "Buffers.h"
        #include "prux.h"
        %}

        .include "macros.asm"
        .include "structs.asm"
        
;;; Interclocking thread runner: Read and write packets
	.def PacketRunner
PacketRunner:
	clr CT.sTH.wFlags, CT.sTH.wFlags, PacketRunnerFlags.fPacketSync ; Init to not having sync
	ldi CT.bOutLen, 0              ; Init 0 says We're working on a 0 length packet
	ldi CT.bOutByte, 0             ; Init 0 says We're working on byte 0 of it (not that that should matter)
	ldi CT.bOutData, 0             ; Init 0 says We're outputting an all zeros byte
	ldi CT.bOutBNum, 0xff          ; Init 255 says But the current byte is all finished
        ldi CT.bInpByte, 0             ; Init 0 says We are reading byte 0 of a packet (if we had sync)
	ldi CT.bInpData, 0             ; Init 0 says The byte we're reading is so far all zeros
	ldi CT.bInpBNum, 7             ; Init 7 says And next bit number to read is bit 7
	ldi CT.bInp1Cnt, 0             ; Init 0 says No run of 1s have been seen on input
	ldi CT.bOut1Cnt, 0             ; Init 0 says we haven't transmitted any run of 1s lately
        ldi CT.bRSRV0, 'a'             ; XXXX: Make visible
        ldi CT.bRSRV1, 'b'             ; XXXX: Make visible
        ldi32 CT.rRSRV2, 0x1eacbeda    ; XXXX: Make visible
	ldi CT.bRSRV43, 'z'            ; XXXX: Make visible

        ;; FALL INTO getNextStuffedBit
	
getNextStuffedBit:  ;; Here to find next output bit to transmit
	sendOTag """GNSB""",CT.bOutBNum      ; report location
	qbne checkForBitStuffing, CT.bOutBNum, 0xff  ; jump ahead if the 0 bit has already been sent
        ;; otherwise FALL INTO getNextOutputByte
	
getNextOutputByte:  ;; Here to fetch next output byte in packet if any
	sendOTag """GNOB""",CT.bOutLen      ; report location
	qbge sendPacketDelimiter, CT.bOutLen, CT.bOutByte ; packet is done if outbyte >= outlen
	ldThreadID r14          ; arg1 to ppbReadOutboundByte
        mov r15, CT.bOutByte    ; arg2 to ppbReadOutboundByte
        jal r3.w2, ppbReadOutboundByte ; go get next byte to send
        mov CT.bOutData, r14    ; move output byte into position
	set CT.sTH.wFlags, CT.sTH.wFlags, PacketRunnerFlags.fByteStuffed ; this byte SHOULD be bitstuffed
        add CT.bOutByte, CT.bOutByte, 1    ; increment bytes sent of this packet
        jmp startNewOutputByte

sendPacketDelimiter:   ;; time to send packet delimiter and discard finished packet
	sendOTag """SPD""",CT.bOutLen       ; report location
        ldi CT.bOutData, 0x7e   ; set up packet delimiter
	clr CT.sTH.wFlags, CT.sTH.wFlags, PacketRunnerFlags.fByteStuffed ; this byte should NOT be bitstuffed

        ;; FALL INTO lookForNextPacket

lookForNextPacket: ;; here to set up next outbound packet if have sync and packets
	sendOTag """LFNP""",CT.sTH.wFlags      ; report in
        ldi CT.bOutByte, 0           ; No matter what we're on byte 0 now
	qbbc startNewOutputByte, CT.sTH.wFlags, PacketRunnerFlags.fPacketSync ; don't try for packets till we have sync
	ldThreadID r14               ; arg1 to ppbReceiveOutboundPacket
        jal r3.w2, ppbReceiveOutboundPacket ; next packetlen or 0 -> r14
        mov CT.bOutLen, r14          ; Save length of next packet or 0

startNewOutputByte:  ;; here to initialize once CT.bOutData has new byte to send
	sendOTag """SNOB""",CT.bOutBNum      ; report in
        ldi CT.bOutBNum, 7           ; next bit to send is the 7th (our protocol is MSB first)
	
        ;; FALL INTO checkForBitStuffing
	
checkForBitStuffing: ;; Here to maybe stuff output bits
	sendOTag """CFBS""",CT.bOut1Cnt      ; report in
	qbbc sendRealDataBit, CT.sTH.wFlags, PacketRunnerFlags.fStuffThisBit ; jump ahead if not stuffing this bit

        ;; FALL INTO stuffAZero
	
stuffAZero: ;; Here to ship a bitstuffed zero
;	startOTagBurst 10         ; start talking buddy (for next 10 cycles)
	sendOTag """SAZ""",CT.bOutBNum      ; report in
	clr r30, r30, CT.bTXDATPin          ; present 0 on TXDAT
	clr CT.sTH.wFlags, CT.sTH.wFlags, PacketRunnerFlags.fStuffThisBit ; mark we did this
	ldi CT.bOut1Cnt, 0                  ; and clear running 1s
	jmp makeFallingEdge                 ; and that's all for this clock
	
sendRealDataBit: ;; Here to send an actual (data or delimiter) bit
	sendOTag """SRDB""",CT.bOutData              ; report in
        qbbc transmitZero, CT.bOutData, CT.bOutBNum  ; Jump ahead if next bit to send a 0
	add CT.bOut1Cnt, CT.bOut1Cnt, 1              ; Count 1s
        qbbc transmitOne, CT.sTH.wFlags, PacketRunnerFlags.fByteStuffed ; Ready to xmit if not stuffing this byte
        qbne transmitOne, CT.bOut1Cnt, 5             ; Also ready if this is not the 5th 1
	set CT.sTH.wFlags, CT.sTH.wFlags, PacketRunnerFlags.fStuffThisBit ; It is the 5th 1, stuff a zero next

        ;; FALL INTO transmitOne

transmitOne: ;; Here to transmit 1
	sendOTag """TMT1""",CT.bOut1Cnt      ; report in
	set r30, r30, CT.bTXDATPin           ; present 1 on TXDAT
	jmp countRealBitSent                 ; count that real bit
        
transmitZero: ;; Here to transmit 0 and clear our running 1s count
	sendOTag """TMT0""",CT.bOut1Cnt      ; report in
	clr r30, r30, CT.bTXDATPin           ; present 0 on TXDAT
        ldi CT.bOut1Cnt, 0                   ; clear running 1s

        ;; FALL INTO countRealBitSent

countRealBitSent:      ;; Here if we sent a real bit (as opposed to bitstuffing 0)
	sub CT.bOutBNum, CT.bOutBNum, 1      ; Record we have transmitted another real bit

        ;; FALL INTO makeFallingEdge
	
makeFallingEdge:  ;; Here to make a falling edge
	sendOTag """MFE""",CT.bOutBNum ; report in as output event
	sendITag """MFE""",CT.bInpBNum ; now report in as an input event
        clr r30, r30, CT.bTXRDYPin      ; TXRDY falls
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
	sendITag """CPIB""",CT.bInp1Cnt ; report in
	loadBit r4.b0, r31, CT.bRXDATPin ; Read RXDAT to r4.b0
	qbgt storeRealInputBit, CT.bInp1Cnt, 5 ; Jump ahead if 5 > run of 1s we've read
        qbne moreThan5ones, CT.bInp1Cnt, 5     ; Jump ahead if 6 (or more?) 1s

	;; otherwise FALL INTO haveExactly5ones
	
haveExactly5ones: ;; Here to eat stuffing or count 6th 1
	sendITag """HX51""",r4.b0       ; report in
        add CT.bInp1Cnt, CT.bInp1Cnt, 1        ; Assume it's another 1
	qbne makeRisingEdge, r4.b0, 0          ; If we guessed right, we're done, go make a rising edge
	
	;; otherwise FALL INTO eatStuffedBit
	
eatStuffedBit: ;; Here to eat a stuffed 0 bit
;	startITagBurst 10         ; start talking buddy (for next 10 cycles)
	sendITag """EBS0""",CT.bInp1Cnt ; report in
	ldi CT.bInp1Cnt, 0                     ; Clear the counter on 0
        jmp makeRisingEdge                     ; And then we're done, go make a rising edge     

moreThan5ones: ;; Here to recognize frame delimiters and errors
	sendITag """MT5""",CT.bInp1Cnt ; report in
	qbne frameError, CT.bInp1Cnt, 6        ; It's a framing error if not exactly six 1s
        add CT.bInp1Cnt, CT.bInp1Cnt, 1        ; Assume it's another 1
        qbne frameError, r4.b0, 0              ; Which is a framing error if so

	;; otherwise FALL INTO completeFrameDelimiter
	
completeFrameDelimiter:  ;; Here we have a (possibly misaligned) complete frame delimiter
	sendITag """CFRD""",CT.sTH.wFlags ; report in
        ldi CT.bInp1Cnt, 0      ; Reset input 1 count
        qbbc achievePacketSync, CT.sTH.wFlags, PacketRunnerFlags.fPacketSync ; If we didn't have sync, get it now
        
	;; otherwise FALL INTO checkExistingAlignment

checkExistingAlignment:  ;; Here we already have packet sync and are looking at a complete frame delimiter
	sendITag """CEXA""", CT.bInpBNum               ; report in
        qbeq handleGoodPacketDelimiter, CT.bInpBNum, 1 ; If at bit number 1, delimiter is aligned, go release full packet
	sendITag """CEXF""", CT.bInpData             ; report in
	
	;; otherwise FALL INTO frameError

frameError:  ;; Here to deal with stuffing failures and misaligned delimiters, whether or not synced
	sendITag """FMER""",CT.bInpByte               ; report in
	qbbc resetAfterDelimiter, CT.sTH.wFlags, PacketRunnerFlags.fPacketSync ; Don't report a problem unless we're synced
	clr CT.sTH.wFlags, CT.sTH.wFlags, PacketRunnerFlags.fPacketSync ; Blow packet sync
	ldThreadID r14          ; arg1 is prudir
	mov r15, CT.bInpByte    ; arg2 is number of bytes written
	mov r16, r6             ; arg3 is first reg
	mov r17, r7
	mov r18, r8
	mov r19, r9
	mov r20, r10
	mov r21, r11
	mov r22, r12
	mov r23, r13
        jal r3.w2, ppbReportFrameError ; Notify upstairs that we got problems down heah
        jmp resetAfterDelimiter

achievePacketSync: ;; Here to achieve packet sync when we didn't already have it
	sendITag """APS""",CT.sTH.wFlags               ; report in
        set CT.sTH.wFlags, CT.sTH.wFlags, PacketRunnerFlags.fPacketSync ; Achieve packet sync
	sendFromThread """PS""", CT.rRunCount.r ; Report that

	;; FALL INTO resetAfterDelimiter

resetAfterDelimiter:  ;; Here to set up for new inbound packet
	sendITag """RAD""",CT.rRunCount.r ; report in
        ldi CT.bInpByte, 0         ; We are on byte 0
        ldi CT.bInpBNum, 7         ; We are on bit 7 of byte 0
        ldi CT.bInpData, 0         ; And that byte is all 0s so far
        ldi CT.bInp1Cnt, 0         ; And we have seen 0 1s in a row
        jmp makeRisingEdge         ; And then we're done with this input bit

handleGoodPacketDelimiter: ;; Here we finally have a finished packet!
	sendITag """HGPD""",CT.bInpByte               ; report in
        qbeq resetAfterDelimiter, CT.bInpByte, 0 ; But if it's zero-length, discard it!
	
sendInFinishedPacket:       ;; Here we know the inbound packet is non-empty
	sendITag """IPSP""",CT.sTH.wFlags   ; report in
        ldThreadID r14                      ; arg1 is prudir
        mov r15, CT.bInpByte                ; arg2 is packet length
        jal r3.w2, ppbSendInboundPacket     ; Push it to DDR for linux!  Foggin finally!
	qbeq resetAfterDelimiter, r14, 0    ; Go set up for another if successful
        suspendThread                       ; If no room to ship we wait :(
        jmp sendInFinishedPacket            ; And then try again

storeRealInputBit: ;; Here if not dealing with bitstuffed 0s, packet delimiters, or framing errors
	sendITag """SRIB""",r4.b0               ; report in
        qbeq gotReal0, r4.b0, 0    ; No storing needed on zeros (because we cleared bInpData to start)
        set CT.bInpData, CT.bInpData, CT.bInpBNum ; Otherwise set the bit we're on
        add CT.bInp1Cnt, CT.bInp1Cnt, 1           ; And increment the running 1s count
        jmp checkEndOfByte                        ; Go see if we've finished a byte

gotReal0:  ;; Here if we're seeing a real data bit 0
	sendITag """GRL0""",CT.bInp1Cnt               ; report in
        ldi CT.bInp1Cnt, 0                        ; Clear running 1s count

        ;; FALL INTO checkEndOfByte

checkEndOfByte: ;; Here to increment and deal with end of byte processing
	sendITag """CEOB""",CT.bInpBNum           ; report in
        sub CT.bInpBNum, CT.bInpBNum, 1           ; Move on to next bit number
        qbne makeRisingEdge, CT.bInpBNum, 0xff    ; Nothing more to do if the bit number hasn't underflowed
        qbbc makeRisingEdge, CT.sTH.wFlags, PacketRunnerFlags.fPacketSync ; Also nothing more to do if not synced
	
        ;; FALL INTO storeThisInputByte

storeThisInputByte: ;; Here to add a finished byte to the packet payload
	sendITag """STIB""",CT.bInpData           ; report in
        ldThreadID r14                            ; arg1 is prudir
        mov r15, CT.bInpByte    ; arg2 is what byte in the packet we just finished
	mov r16, CT.bInpData    ; arg3 is byte value to store
        jal r3.w2, ppbWriteInboundByte ; go store this byte

        ;; FALL INTO setupForNextInputByte
        
setupForNextInputByte:  ;; Here to initialize for reading another byte
	sendITag """SFNB""",CT.bInpByte ; report in
        add CT.bInpByte,  CT.bInpByte, 1 ; Move on to next byte
        ldi CT.bInpData, 0               ; Clear the byte data itself
        ldi CT.bInpBNum, 7               ; And set the bit number coming next

        ;; FALL INTO makeRisingEdge
        
makeRisingEdge: ;; Here to make a rising clock edge
	sendITag """MRE""",CT.rRunCount.r      ; report in as input event
	sendOTag """MRE""",CT.rRunCount.r      ; now report in as output event
        set r30, r30, CT.bTXRDYPin        ; TXRDY rises
	add CT.rRunCount.r,  CT.rRunCount.r, 1 ; Count rising edges
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
       
