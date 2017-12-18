	.cdecls "prux.h"
	
;;;;;;
;;; STRUCTURE DECLARATIONS

;;; Demo struct: STATE_INFO
STATE_INFO:     .struct
RXRDY_COUNT:    .ubyte
RXDAT_COUNT:    .ubyte
RXRDY_STATE:    .ubyte
RXDAT_STATE:    .ubyte
STATE_INFOLen: .endstruct
	
LiveCounts:     .sassign R5, STATE_INFO
        
;;; ThreadCoord: A length (in bytes) and an offset (in registers)
ThreadCoord:      .struct
bOffsetRegs:    .ubyte      ; offset in registers  (to load in r0.b0)
bLenBytes:      .ubyte      ; length in bytes      (to load in r0.b1)
ThreadCoordLen:  .endstruct

;;; ThreadLoc: A union of a ThreadCoord and a word to load
ThreadLoc:      .union
sTC:    .tag ThreadCoord
w:      .ushort                     
        .endunion

;;; ThreadHeader: Enough info to save, load, and context switch a thread
ThreadHeader:   .struct
sThis:          .tag ThreadLoc  ; Our thread storage location
sNext:          .tag ThreadLoc  ; Next guy's storage location
	
bID:            .ubyte  ; thread id (prudir for 0..2, 3 for linux)
bFlags:         .ubyte  ; flags
wResAddr:       .ushort ; Resume address after context switch	
ThreadHeaderLen:       .endstruct

;;; IOThread: Everything needed for a prudir state machine
IOThread:       .struct
sTH:            .tag ThreadHeader ; sTH takes two regs

bTXRDYPin:      .ubyte  ; Transmit Ready R30 Pin Number
bTXDATPin:      .ubyte  ; Transmit Data  R30 Pin Number
bRXRDYPin:      .ubyte  ; Receive Ready  R31 Pin Number
bRXDATPin:      .ubyte  ; Receive Data   R31 Pin Number

bOutData:       .ubyte  ; current bits being shifted out
bOutBCnt:       .ubyte  ; count of bits remaining to shift out
bInpData:       .ubyte  ; current bits being shifted in
bInpBCnt:       .ubyte  ; count of bits remaining to shift in

bPrevOut:       .ubyte  ; last bit sent 
bThisOut:       .ubyte  ; current bit to sent
bOut1Cnt:       .ubyte  ; current count of output 1s sent
bInp1Cnt:       .ubyte  ; current count of input 1s received

rTXDATMask:     .uint   ; 1<<TXDAT_PN
rRSRV3:         .uint   ; reserved
rRSRV4:         .uint   ; reserved
IOThreadLen:   .endstruct
        
;;; LinuxThread: Everything needed for packet processing
LinuxThread:    .struct        
sTH:            .tag ThreadHeader ; sTH takes two regs
LinuxThreadLen: .endstruct     

;;; CT is the Current Thread!  It lives in R6-R13!
	.eval IOThreadLen/4, CTRegs
	.eval 6, CTBaseReg
	.asg R6, CTReg
CT:     .sassign CTReg, IOThread

;;;;;;
;;; MACRO DEFINITIONS
	
;;;;;;;;
;;;: macro sendVal: Print two strings and a value
;;;  INPUTS:
;;;    STR1: First string to print
;;;    STR2: Second string to print
;;;    VAL: Value to print (reg or imm)
;;;  OUTPUTS: None
;;;  NOTES:
;;;  - WARNING: MUST NOT BE USED IN LEAF FUNCTIONS!
;;;  - TRASHES CALLER-SAVE REGS
	;int CSendVal(const char * str, uint32_t val)
	.ref CSendVal
sendVal:        .macro STR1, STR2, REGVAL
	.sect ".rodata:.string"
$M1?:  .cstring STR1
$M2?:  .cstring STR2
	.text
	sub r2, r2, 2           ; Two bytes on stack
	sbbo &r3.w2, r2, 0, 2   ; Save current R3.w2
        mov r16, REGVAL         ; Get value to report before trashing anything else
        ldi32 r14, $M1?         ; Get string1
        ldi32 r15, $M2?         ; Get string2
        jal r3.w2, CSendVal     ; Call CSendVal (ignore return)
	lbbo &r3.w2, r2, 0, 2   ; Restore r3.w2 
        add r2, r2, 2           ; Pop stack
        .endm

;;;;;;;;;
;;;: macro loadBit: Copy SRCREG bit BITNUM to bottom of DESTREG
;;;  INPUTS:
;;;    SRCREG: Source register field; REG
;;;    BITNUM: Number of bit (0 == LSB) to copy; OP(31)
;;;    DSTREG: Destination register field; REG
;;;  OUTPUTS:
;;;    DESTREG is cleared except its bottom bit is SRCREG[BITNUM]
loadBit:        .macro DESTREG, SRCREG, BITNUM
        lsr DESTREG, SRCREG, BITNUM ; Position desired bit at bottom of destreg
        and DESTREG, DESTREG, 1     ; Flush the rest
        .endm

;;;;;;;;
;;;: macro enterFunc: Function prologue
;;;  INPUTS:
;;;    BYTES: Number of bytes to save on stack, starting with r3.w2
;;;  OUTPUTS: NONE
;;;  NOTES:
;;;  - BYTES can be 0 or 2+
;;;  - BYTES == 0 means this is a 'leaf' function that will not
;;;    call any other functions
enterFunc:      .macro BYTES
        .if BYTES > 0
        sub r2, r2, BYTES
        sbbo &r3.w2, r2, 0, BYTES
        .endif
        .endm

;;;;;;;;
;;;: macro exitFunc: Function epilogue
;;;  INPUTS:
;;;    BYTES: Number of bytes to restore from stack, starting with
;;;r3.w2
;;;  OUTPUTS: NONE
;;;  NOTES:
;;;  - BYTES better damn match that in the associated enterFunc
exitFunc:      .macro BYTES
        .if BYTES > 0
        lbbo &r3.w2, r2, 0, BYTES ; Restore regs
        add r2, r2, BYTES         ; Pop stack
        .endif
        jmp r3.w2                 ; And return
        .endm


;;;;;;;;
;;;: macro initThis: Initialize the current thread state
;;;  INPUTS:
;;;  - THISSHIFT: How many regs between CT and where this guy's stored in scratchpad
;;;  - THISBYTES: How many bytes of state starting at CT are in this guy's state
;;;  - ID: The ID number of this thread
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
	.endm

;;;;;;;;
;;;: macro initNext: Initialize the next portion of the current thread state
;;;  INPUTS:
;;;  - NEXTSHIFT: How many regs between CT and where the next guy's stored in scratchpad
;;;  - NEXTBYTES: How many bytes of state starting at CT are in the next guy's state
;;;  OUTPUTS: NONE
;;;  NOTES:
;;;  - Intended for one-time use in tandem with initThis
initNext:  .macro NEXTSHIFT,NEXTBYTES
	ldi CT.sTH.sNext.sTC.bOffsetRegs, NEXTSHIFT
        ldi CT.sTH.sNext.sTC.bLenBytes, NEXTBYTES
        .endm

;;;;;;;;
;;;: macro saveThisThread: Save this thread's state in its place in the scratchpad
;;;  INPUTS: NONE
;;;  OUTPUTS: NONE
;;;  NOTES:
;;;  - Used during initialization and context switching
saveThisThread: .macro
        mov r0.w0, CT.sTH.sThis.w  ; r0.b0 <- this bOffsetRegs, r0.b1 <- this bLenBytes
        xout PRUX_SCRATCH, &CT, b1 ; store this thread
        .endm

;;;;;;;;
;;;: macro loadNextThread: Read in the next thread's state from its place in the scratchpad
;;;  INPUTS: NONE
;;;  OUTPUTS: NONE
;;;  NOTES:
;;;  - Used during context switching
loadNextThread: .macro
        mov r0.w0, CT.sTH.sNext.w ; r0.b0 <- next bOffsetRegs, r0.b1 <- next bLenBytes
        xin PRUX_SCRATCH, &CT, b1 ; load next thread
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
                

;;;;;;;;
;;;: macro suspendThread: Sleep current thread
;;;  INPUTS: NONE
;;;  OUTPUTS: NONE
;;;  NOTES:
;;;  - Generates an arbitrary delay (of 30ns or more)
;;;  - Trashes everything but R2, R3.w2, and CT
suspendThread: .macro
        jal CT.sTH.wResAddr, contextSwitch
        .endm
                

;;; LINUX thread runner 
LinuxThreadRunner:
        jal r3.w2, processPackets ; Surface to C level, check for linux action
        suspendThread             ; Then context switch
        jmp LinuxThreadRunner     ; Then try again

;;; Idle thread runner 
IdleThreadRunner:
        suspendThread           ; Just context switch
        jmp IdleThreadRunner    ; Then try again


;;; Timing thread runner: Sends a 'timer' packet every 128M iterations
ttr0:   sendVal PRUX_STR,""" timer """,CT.rRSRV3 ; Report counter value
ttr1:   suspendThread                            ; Now context switch
TimingThreadRunner:
	add CT.rRSRV3, CT.rRSRV3, 1 ; Increment secret counter
	lsl r0, CT.rRSRV3, 5       ; Keep low order 27 bits
	qbeq ttr0, R0, 0           ; Report in if they're all zero
        jmp ttr1                   ; Either way then sleep

        .text
        .def mainLoop
mainLoop:
	enterFunc 6

        sendVal PRUX_STR,""" entering main loop""",r2 ; Say hi
	.ref processPackets
l0:     
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
	exitFunc 6
        
startStateMachines:
	enterFunc 2
        ;; DEMO CODE INIT
	;; Clear counts
	zero &LiveCounts,STATE_INFOLen
        ;; Read initial pin states
	loadBit LiveCounts.RXRDY_STATE, r31, PRUDIR1_RXRDY_R31_BIT  ; pru0 SE, pru1 NW
	loadBit LiveCounts.RXDAT_STATE, r31, PRUDIR1_RXDAT_R31_BIT  ; pru0 SE, pru1 NW
        ;; END DEMO CODE INIT
	
	;; Init threads by hand
        initThis 0*CTRegs, IOThreadLen, 0, IdleThreadRunner ; Thread ID 0 at shift 0
        initNext 1*CTRegs, IOThreadLen             ; Info for thread 1
        saveThisThread                             ; Stash thread 0
	
        initThis 1*CTRegs, IOThreadLen, 1, TimingThreadRunner ; Thread ID 1 at shift CTRegs
	initNext 2*CTRegs, IOThreadLen             ; Info for thread 2
        saveThisThread                             ; Stash thread 1
	
        initThis 2*CTRegs, IOThreadLen, 2, IdleThreadRunner ; Thread ID 2 at shift 2*CTRegs
	initNext 3*CTRegs, LinuxThreadLen          ; Info for thread 3
        saveThisThread                             ; Stash thread 2
	
        initThis 3*CTRegs, LinuxThreadLen, 3,LinuxThreadRunner ; Thread ID 3 at shift 3*CTRegs
        initNext 0*CTRegs, IOThreadLen             ; Next is back to thread 0
        saveThisThread                             ; Stash thread 3
        ;; Done with by-hand thread inits

        ;; Report in             
        sendVal PRUX_STR,""" Releasing the hounds""", CT.sTH.wResAddr ; Report in

;; l99:
;;         jal r3.w2, processPackets
;;         jmp l99

        ;; Thread 3 is still loaded
        jmp CT.sTH.wResAddr     ; Resume it
	exitFunc 2

        .def advanceStateMachines
advanceStateMachines:
	enterFunc 6             ; Save R3.w2 and R4 on stack
	
	loadBit r4, r31, 2     ; rxrdy (r31.t2) to r4
        qbeq asm1, r4, LiveCounts.RXRDY_STATE ; jump if no change
	mov LiveCounts.RXRDY_STATE, r4        ; else update retained state,
        add LiveCounts.RXRDY_COUNT, LiveCounts.RXRDY_COUNT, 1 ; increment, and
	sendVal PRUX_STR,""" RXRDY""",LiveCounts.RXRDY_COUNT ; report change

asm1:
        loadBit r4, r31, 14    ; rxdat (r31.t14) to r4
        qbeq asm2, r4, LiveCounts.RXDAT_STATE ; jump if no change
	mov LiveCounts.RXDAT_STATE, r4        ; else update retained state
        add LiveCounts.RXDAT_COUNT, LiveCounts.RXDAT_COUNT, 1 ; increment, and
	sendVal PRUX_STR,""" RXDAT""",LiveCounts.RXDAT_COUNT ; report change

asm2:   exitFunc 6              ; Done

	;; void copyOutScratchPad(uint8_t * packet, uint16_t len)
        ;; R14: ptr to destination start
        ;; R15: bytes to copy
        ;; R17: index
        .def copyOutScratchPad
copyOutScratchPad:
        ;; NOTE NON-STANDARD PROLOGUE
	sub r2, r2, 8           ; Get room for first two regs of CT
        sbbo &r6, r2, 0, 8      ; Store r6 & r7 on stack
	sbbo &r7, r14, 1, 1     ; Store ID at packet[1]
	lsr r7, r7, 16          ; Right justify resume address
	sbbo &r7, r14, 2, 2     ; Store resume address at packet[2..3]
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
        lbbo &r6, r2, 0, 8      ; Restore r6 and r7
        add r2, r2, 8           ; Pop stack
        JMP r3.w2               ; Return

	;; unsigned processOutboundITCPacket(uint8_t * packet, uint16_t len);
	;; R14: packet
        ;; R15: len
        .def processOutboundITCPacket
processOutboundITCPacket:
        qbne hasLen, r15, 0
        ldi r14, 0
        jmp r3.w2               ; Return 0
hasLen:
        lbbo &r15, r14, 0, 1    ; R15 = packet[0]
        add r15, r15, 3         ; Add 3 to show we were here
        sbbo &r15, r14, 0, 1    ; packet[0] = R15
        ldi r14, 1
        jmp r3.w2               ; Return 1
        
