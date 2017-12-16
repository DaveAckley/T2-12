;;; prux_sbst3.asm: A 3-way parallel SBsT packet process for PRU
;;; 
;;; Copyright (C) 2017 The Regents of the University of New Mexico
;;; 
;;; This software is licensed under the terms of the GNU General Public
;;; License version 2, as published by the Free Software Foundation, and
;;; may be copied, distributed, and modified under those terms.
;;;
;;; This program is distributed in the hope that it will be useful,
;;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;;; GNU General Public License for more details.

	.cdecls "prux.h"

;;; Show symbol substitutions in listing
        .sslist 	

	;; STRUCTURE DECLARATIONS

;;; Demo struct: STATE_INFO
STATE_INFO:     .struct
RXRDY_COUNT:    .ubyte
RXDAT_COUNT:    .ubyte
RXRDY_STATE:    .ubyte
RXDAT_STATE:    .ubyte
StateInfoLen:   .endstruct
	
LiveCounts:     .sassign R5, STATE_INFO
        
;;;;;;
;;; IOThread: Everything needed for a prudir state machine
	
	;; 3 bits of regs == 8 regs per IOTHREAD
	.eval 3, IOThreadBits
        .eval (1<<IOThreadBits), IOThreadRegs
        .eval (4*IOThreadRegs), IOThreadBytes

IOThread:       .struct
bThisID:        .ubyte  ; this context id (0..2) 
bNextID:        .ubyte  ; next context id (0..2)
bPrevID:        .ubyte  ; prev context id (0..2)
bFlags:         .ubyte  ; flags

bTXRDYPin:      .ubyte  ; Transmit Ready R30 Pin Number
bTXDATPin:      .ubyte  ; Transmit Data  R30 Pin Number
bRXRDYPin:      .ubyte  ; Receive Ready  R31 Pin Number
bRXDATPin:      .ubyte  ; Receive Data   R31 Pin Number

wResAddr:       .ushort ; Resume address after context switch
bOut1Cnt:       .ubyte  ; current count of output 1s sent
bInp1Cnt:       .ubyte  ; current count of input 1s received

bOutData:       .ubyte  ; current bits being shifted out
bOutBCnt:       .ubyte  ; count of bits remaining to shift out
bInpData:       .ubyte  ; current bits being shifted in
bInpBCnt:       .ubyte  ; count of bits remaining to shift in

bPrevOut:       .ubyte  ; last bit sent 
bThisOut:       .ubyte  ; current bit to send
wRSRV2:         .ushort ; reserved

rTXDATMask:     .uint   ; 1<<TXDATPin (cached)
rRSRV3:         .uint   ; reserved
rRSRV4:         .uint   ; reserved
IOThreadStructLen:   .endstruct

        .if     IOThreadBytes != IOThreadStructLen
        .emsg "ERROR - IOTHREAD struct size inconsistency"
        .endif

        
;;; CT is the Current Thread!  It lives in R6-R13!
	.asg R6, CTReg
CT:     .sassign CTReg, IOThread

	;int sendVal(const char * str, uint32_t val)
	.ref sendVal            

;;;;;;
;;; MACROS

;;;
;;; SENDVAL: Print two strings and a value
;;;  INPUTS:
;;;    STR1: First string to print
;;;    STR2: Second string to print
;;;    VAL: Value to print (reg or imm)
;;;  OUTPUTS: None
;;;  NOTES:
;;;  - WARNING: MUST NOT BE USED IN LEAF FUNCTIONS!
;;;  - TRASHES CALLER-SAVE REGS
SENDVAL:        .macro STR1, STR2, VAL
	.sect ".rodata:.string"
$M1?:  .cstring STR1
$M2?:  .cstring STR2
	.text
        mov r16, VAL            ; Get value to report (before trashing regs)
        ldi32 r14, $M1?         ; Get string1
        ldi32 r15, $M2?         ; Get string2
        jal r3.w2, sendVal      ; Call sendVal (ignore return)
        .endm

;;;	
;;; LOADBIT: Copy SRCREG bit BITNUM to bottom of DESTREG
;;;  INPUTS:
;;;    SRCREG: Source register field; REG
;;;    BITNUM: Number of bit (0 == LSB) to copy; OP(31)
;;;    DSTREG: Destination register field; REG
;;;  OUTPUTS:
;;;    DESTREG is cleared except its bottom bit is SRCREG[BITNUM]
LOADBIT:        .macro DESTREG, SRCREG, BITNUM
        lsr DESTREG, SRCREG, BITNUM ; Position desired bit at bottom of destreg
        and DESTREG, DESTREG, 1     ; Flush the rest
        .endm

;;;	
;;; SUSPEND: Sleep current thread 
;;;  INPUTS: NONE
;;;  OUTPUTS: NONE
;;;  NOTES:
;;;  - Generates an arbitrary delay (of 30ns or more)
;;;  - Trashes everything but CT
SUSPEND:        .macro
        jal CT.wResAddr, contextSwitch
        .endm
        
;;;
;;; ENTERFUNC: Function prologue
;;;  INPUTS:
;;;    BYTES: Number of bytes to save on stack, starting with r3.w2
;;;  OUTPUTS: NONE
;;;  NOTES:
;;;  - BYTES can be 0 or 2+
;;;  - BYTES == 0 means this is a 'leaf' function that will not
;;;    call any other functions
ENTERFUNC:      .macro BYTES
        .if BYTES > 0
        sub r2, r2, BYTES
        sbbo &r3.w2, r2, 0, BYTES
        .endif
        .endm
        
;;;
;;; EXITFUNC: Function epilogue
;;;  INPUTS:
;;;    BYTES: Number of bytes to restore from stack, starting with r3.w2
;;;  OUTPUTS: NONE
;;;  NOTES:
;;;  - BYTES better damn match that in the associated ENTERFUNC
EXITFUNC:      .macro BYTES
        .if BYTES > 0
	lbbo &r3.w2, r2, 0, BYTES ; Restore regs
        add r2, r2, BYTES         ; Pop stack
        .endif
	jmp r3.w2                 ; And return
        .endm

;;;;;;
;;; ASSEMBLER MAIN LOOP
	.text
        .def mainLoop
mainLoop:
	.ref processPackets       ; C function
        jal r3.w2, processPackets ; Return == 0 if firstPacket done
	qbne mainLoop, r14, 0     ; Wait for that before initting state machines
	jal r3.w2, initStateMachines
l1:     jal r3.w2, advanceStateMachines
        jal r3.w2, processPackets
        jmp l1
	
        .text
        .def addfuncasm
addfuncasm:     ENTERFUNC 2     ; Store r3.w2 (so we can use SENDVAL)
        add r14, r15, r14       ; Compute function, result to r14
	SENDVAL PRUX_STR,""" addfuncasm sum""",r14 ; Report it
	EXITFUNC 2              ; Restore r3.w2 
        jmp r3.w2               ; Return
        
        
;;;;;;
;;; STATE MACHINE SUPPORT
	
initStateMachines:      ENTERFUNC 2 ; Save r3.w2 (for SENDVAL)
	;; Clear counts
	zero &LiveCounts,StateInfoLen
	
        ;; Read initial pin states
	LOADBIT LiveCounts.RXRDY_STATE, r31, PRUDIR1_RXRDY_R31_BIT  ; pru0 SE, pru1 NW
	LOADBIT LiveCounts.RXDAT_STATE, r31, PRUDIR1_RXDAT_R31_BIT  ; pru0 SE, pru1 NW

	;; Clear CT
	zero &CT,IOThreadBytes             ; so e.g. this_id = next_id = prev_id = 0
	loop el1, 3                        ; three times around
        ;; XXX ADDITIONAL INITS HERE
	lsl r0.b0, CT.bThisID, IOThreadBits ; r0.b0 = this_id*8
        xout PRUX_SCRATCH, &CT, IOThreadBytes ; Save 'initted' context
	add CT.bThisID, CT.bThisID, 1     ; ++this_id
	mov CT.bNextID, CT.bThisID        ; next_id = this_id
	mov CT.bPrevID, CT.bThisID        ; prev_id = this_id
el1:    
        ;; Load thread 1
        ldi r0.b0, 1<<3
        xin PRUX_SCRATCH, &CT, IOThreadBytes
        
        SENDVAL PRUX_STR,""" initStateMachines""", r0.b0 ; Report in
	EXITFUNC 2                        ; Return

;;;;;;;;;;;;;;;
;;; SCHEDULER

contextSwitch:
        lsl r0.b0, CT.bThisID, IOThreadBits ; Get our reg shift
        xout PRUX_SCRATCH, &CT, IOThreadBytes ; Stash current thread
        ;; FALL THROUGH
	
nextContext:
        lsl r0.b0, CT.bNextID, IOThreadBits ; Get next reg shift
        xin PRUX_SCRATCH, &CT, IOThreadBytes ; Load next thread
	jmp CT.wResAddr                      ; and resume it
        
        .def advanceStateMachines
advanceStateMachines:   ENTERFUNC 6
	
	LOADBIT r4, r31, 2                    ; rxrdy (r31.t2) to r4
        qbeq asm1, r4, LiveCounts.RXRDY_STATE ; jump if no change
	mov LiveCounts.RXRDY_STATE, r4        ; else update retained state,
        add LiveCounts.RXRDY_COUNT, LiveCounts.RXRDY_COUNT, 1 ; increment, and
	SENDVAL PRUX_STR,""" RXRDY""",LiveCounts.RXRDY_COUNT ; report change

asm1:
        LOADBIT r4, r31, 14                   ; rxdat (r31.t14) to r4
        qbeq asm2, r4, LiveCounts.RXDAT_STATE ; jump if no change
	mov LiveCounts.RXDAT_STATE, r4        ; else update retained state
        add LiveCounts.RXDAT_COUNT, LiveCounts.RXDAT_COUNT, 1 ; increment, and
	SENDVAL PRUX_STR,""" RXDAT""",LiveCounts.RXDAT_COUNT ; report change

asm2:
        EXITFUNC 6
	

	;; void copyOutScratchPad(uint8_t * packet, uint16_t len)
        ;; R14: ptr to destination start
        ;; R15: bytes to copy
	;; CTReg: buffer for XIN data
        ;; R17: index
        .def copyOutScratchPad
copyOutScratchPad:
        ;; NOTE NON-STANDARD PROLOGUE
	sub r2, r2, 4           ; Get room for first reg of CT
        sbbo &CTReg, r2, 0, 4   ; Store first reg of CT on stack

        ldi r17,0               ; index = 0
        min r15, r15, 3*IOThreadBytes ; don't read beyond the three threads
cosp1:
	qbge cosp2, r15, r17     ; Done when idx reaches len
	lsr r0.b0, r17, 2        ; Get reg of byte: at idx/4
	xin PRUX_SCRATCH, &CTReg, 4 ; Scratchpad to CT, shifted 
	and r0.b0, r17, 3        ; Get byte within reg at idx % 4
	lsl r0.b0, r0.b0, 3      ; b0 = (idx%4)*8
	lsr CTReg,CTReg,r0.b0    ; CT >>= b0
	sbbo &CTReg, r14, r17, 1 ; Stash next byte at R14[R17]
        add r17, r17, 1          ; One more byte to shift bits after
        JMP cosp1
cosp2:
        ;; NOTE NON-STANDARD EPILOGUE
        lbbo &CTReg, r2, 0, 4   ; Restore first reg of CT
        add r2, r2, 4           ; Pop stack
        jmp r3.w2               ; Return

	;; unsigned processOutboundITCPacket(uint8_t * packet, uint16_t len);
	;; R14: packet
        ;; R15: len
        .def processOutboundITCPacket
processOutboundITCPacket:
        qbne hasLen, r15, 0
        ldi r14, 0
        jmp r3.w2               ; Return 0
hasLen:
        lbbo &r15, r14, 0, 1    ; r15 = packet[0]
        add r15, r15, 3         ; Add 3 to show we were here
        sbbo &r15, r14, 0, 1    ; packet[0] = R15
        ldi r14, 1
        jmp r3.w2               ; Return 1
       
