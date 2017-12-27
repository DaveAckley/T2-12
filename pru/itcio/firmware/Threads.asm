;;; -*- asm -*-
	
        .cdecls C,LIST
        %{
        #include "Threads.h"
        #include "prux.h"
        %}

        .include "macros.asm"
        .include "structs.asm"
        
;;;;;;;;
;;;: macro initThis: Initialize the current thread state
;;;  INPUTS:
;;;  - THISSHIFT: How many regs between CT and where this guy's stored in scratchpad
;;;  - THISBYTES: How many bytes of state starting at CT are in this guy's state
;;;  - ID: The ID number of this thread (0..3)
;;;  - RESUMEADDR: Where this thread should start executing when it is first resumed
;;;  OUTPUTS: NONE
;;;  NOTES:
;;;  - Intended for one-time use
;;;  - Many Bothans died to bring us this information: $CODE
initThis: .macro THISSHIFT,THISBYTES,ID,RESUMEADDR
        zero &CT,IOThreadLen                      ; Clear CT to start
        ldi CT.sTH.sThis.sTC.bOffsetRegs, THISSHIFT
        ldi CT.sTH.sThis.sTC.bLenBytes, THISBYTES
        ldi CT.sTH.bID, ID
        ldi CT.sTH.bFlags, 0
	ldi CT.sTH.wResAddr,$CODE(RESUMEADDR)
	
	.if ID == 0
        ;; PRUDIR 0
        ldi CT.bTXRDYPin, PRUDIR0_TXRDY_R30_BIT
        ldi CT.bTXDATPin, PRUDIR0_TXDAT_R30_BIT
        ldi CT.bRXRDYPin, PRUDIR0_RXRDY_R31_BIT
        ldi CT.bRXDATPin, PRUDIR0_RXDAT_R31_BIT
        ldi CT.rTXDATMask, 1<<PRUDIR0_TXDAT_R30_BIT
	
        .elseif ID == 1
        ;; PRUDIR 1
        ldi CT.bTXRDYPin, PRUDIR1_TXRDY_R30_BIT
        ldi CT.bTXDATPin, PRUDIR1_TXDAT_R30_BIT
        ldi CT.bRXRDYPin, PRUDIR1_RXRDY_R31_BIT
        ldi CT.bRXDATPin, PRUDIR1_RXDAT_R31_BIT
        ldi CT.rTXDATMask, 1<<PRUDIR1_TXDAT_R30_BIT
	
        .elseif ID == 2
        ;;PRUDIR 2
	ldi CT.bTXRDYPin, PRUDIR2_TXRDY_R30_BIT
        ldi CT.bTXDATPin, PRUDIR2_TXDAT_R30_BIT
        ldi CT.bRXRDYPin, PRUDIR2_RXRDY_R31_BIT
        ldi CT.bRXDATPin, PRUDIR2_RXDAT_R31_BIT
        ldi CT.rTXDATMask, 1<<PRUDIR2_TXDAT_R30_BIT

        .endif
	.endm

;;;;;;;;;;;;;;;
;;; SCHEDULER

;;;;;;;;
;;;: target contextSwitch: Switch to next thread
contextSwitch:
        saveThisThread
        ;; FALL THROUGH
;;;;;;;;
;;;: target nextContext: Load next thread and resume it
nextContext:
	loadNextThread              ; Pull in next thread
        jmp CT.sTH.wResAddr         ; and resume it
                

;;; LINUX thread runner 
LinuxThreadRunner:
	qbbs ltr1, r31, HOST_INT_BIT   ; Process packets if host int from linux is set..
        add LT.wResumeCount,  LT.wResumeCount, 1 ; Otherwise, bump resume count
        qbne ltr2, LT.wResumeCount, 0  ; And do processing if it wrapped
ltr1:   jal r3.w2, processPackets      ; Surface to C level, check for linux action
ltr2:   resumeAgain                    ; Save, switch, resume at LinuxThreadRunner

;;; Idle thread runner 
IdleThreadRunner:
	resumeNextThread               ; Switch without save then resume at IdleThreadRunner


;;; Timing thread runner: Sends a 'timer' packet every 256M iterations
ttr0:   sendVal PRUX_STR,""" timer """,CT.rRunCount.r ; Report counter value
ttr1:   suspendThread                            ; Now context switch
TimingThreadRunner:
	add CT.rRunCount.r, CT.rRunCount.r, 1 ; Increment run count
	lsl r0, CT.rRunCount.r, 4       ; Keep low order 28 bits
	qbeq ttr0, R0, 0           ; Report in if they're all zero
        jmp ttr1                   ; Either way then sleep

        .text
        .def mainLoop
mainLoop:
	enterFunc 6
l0:     
	.ref processPackets
        jal r3.w2, processPackets ; Return == 0 if firstPacket done
	qbne l0, r14, 0           ; Wait for that before initting state machines
	
	jal r3.w2, startStateMachines ; Not expected to return
	
        sendVal PRUX_STR,""" unexpected return to main loop""",r2 ; Say bye
        exitFunc 6

        .text
        .def addfuncasm
addfuncasm:
	enterFunc 6
        add r4, r15, r14        ; Compute function, result to r4
	sendVal PRUX_STR,""" addfuncasm sum""",r4 ; Report it
	mov r14, r4                               ; and return it
	exitFunc 6
        
startStateMachines:
	enterFunc 2
	
	;; Init threads by hand
	.ref PacketRunner
        initThis 0*CTRegs, IOThreadLen, 0, PacketRunner ; Thread ID 0 at shift 0
        initNext 1*CTRegs, IOThreadLen             ; Info for thread 1
        saveThisThread                             ; Stash thread 0
	
        initThis 1*CTRegs, IOThreadLen, 1, PacketRunner ; Thread ID 1 at shift CTRegs
	initNext 2*CTRegs, IOThreadLen             ; Info for thread 2
        saveThisThread                             ; Stash thread 1
	
        initThis 2*CTRegs, IOThreadLen, 2, PacketRunner ; Thread ID 2 at shift 2*CTRegs
	initNext 3*CTRegs, LinuxThreadLen          ; Info for thread 3
        saveThisThread                             ; Stash thread 2
	
        initThis 3*CTRegs, LinuxThreadLen, 3, LinuxThreadRunner ; Thread ID 3 at shift 3*CTRegs
	ldi32 LT.rCTRLAddress, PRUX_CTRL_ADDR      ; Precompute per-PRU CTRL regs base address
        initNext 0*CTRegs, IOThreadLen             ; Next is back to thread 0
        saveThisThread                             ; Stash thread 3
        ;; Done with by-hand thread inits

        ;; Report in             
        sendVal PRUX_STR,""" Releasing the hounds""", CT.sTH.wResAddr ; Report in

        ;; Thread 3 is still loaded
        jmp CT.sTH.wResAddr     ; Resume it
	exitFunc 2

	;; void copyOutScratchPad(uint8_t * packet, uint16_t len)
        ;; R14: ptr to destination start
        ;; R15: bytes to copy
        ;; R17: index
        .def copyOutScratchPad
copyOutScratchPad:
        ;; NOTE NON-STANDARD PROLOGUE
	sub r2, r2, 8           ; Get room for first two regs of CT
        sbbo &CT, r2, 0, 8      ; Store CT & CT+1 on stack
	add r14, r14, 4         ; Move up to start of scratchpad save area
        sub r15, r15, 4         ; Adjust for room we used

        ldi r17,0               ; index = 0
        min r15, r15, 4*30      ; can the xfr shift, itself, wrap?
cosp1:
	qbge cosp2, r15, r17     ; Done when idx reaches len
	lsr r0.b0, r17, 2        ; Get reg of byte: at idx/4
	xin PRUX_SCRATCH, &r6, 4 ; Scratchpad to r6, shifted 
	and r0.b0, r17, 3        ; Get byte within reg at idx % 4
	lsl r0.b0, r0.b0, 3      ; b0 = (idx%4)*8
	lsr r6, r6, r0.b0        ; CT >>= b0
	sbbo &r6, r14, r17, 1    ; Stash next byte at r14[r17]
        add r17, r17, 1          ; One more byte to shift bits after
        jmp cosp1
cosp2:
        ;; NOTE NON-STANDARD EPILOGUE
        lbbo &CT, r2, 0, 8      ; Restore CT and CT+1
        add r2, r2, 8           ; Pop stack
        JMP r3.w2               ; Return

