;;; -*- asm -*-
	
        .cdecls C,LIST
        %{
        #include "PacketRunner.h"
        #include "prux.h"
        %}

        .include "macros.asm"
        .include "structs.asm"
        
;;; Interclocking thread runner: Read and write packets
	.def PacketRunner
PacketRunner:
        clr r30, r30, CT.bTXDATPin     ; Init to output 0
	;; Here to make a falling edge
ictr1:  clr r30, r30, CT.bTXRDYPin     ; TXRDY falls
	saveResumePoint ictr3
	
	;; Our clock low loop
ictr2:  resumeNextThread               ; To pause or wait after falling edge
ictr3:  .if ON_PRU == 0
          qbbc ictr2, r31, CT.bRXRDYPin  ; PRU0 is MATCHER: if me 0, you 0, we're good
        .else                            ; ON_PRU == 1
	  qbbs ictr2, r31, CT.bRXRDYPin  ; PRU1 is MISMATCHER: if me 0, you 1, we're good
        .endif  

	;; Here to make a rising edge
        set r30, r30, CT.bTXRDYPin        ; TXRDY rises

        add CT.rRunCount.r,  CT.rRunCount.r, 1 ; bump count
        qbne ictr4, CT.rRunCount.b.b0, 0       ; Wait for 1 in 256 count
	
        .ref orbFrontPacketLen
        mov r14, CT.sTH.bID     ; arg is prudir
        jal r3.w2, orbFrontPacketLen ; outbound packet len -> r14
	
	qbeq ictr4a, r14, 0     ; Jump ahead if zero -> no packets

        sendFromThread """DP""",r14 ; Report packet length

        mov r14, CT.sTH.bID     ; Get prudir again
        .ref orbDropFrontPacket 
        jal r3.w2, orbDropFrontPacket ; Toss that guy for now

ictr4a:

ictr4:  saveResumePoint ictr6
	
	;; Our clock high loop
ictr5:  resumeNextThread                 ; To wait, or wait more, after rising edge
ictr6:  .if ON_PRU == 0 
          qbbs ictr5, r31, CT.bRXRDYPin  ; PRU0 is MATCHER: if me 1, you 1, we're good
        .else                            ; ON_PRU == 1
	  qbbc ictr5, r31, CT.bRXRDYPin  ; PRU1 is MISMATCHER: if me 1, you 0, we're good
        .endif  
        jmp ictr1               

