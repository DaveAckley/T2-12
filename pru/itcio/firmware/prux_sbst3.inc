;;; -*- asm -*-
	
;;;;;;
;;; STRUCTURE DECLARATIONS

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

;;; B4: A struct of four bytes
B4:     .struct
b0:        .ubyte
b1:        .ubyte
b2:        .ubyte
b3:        .ubyte
        .endstruct
	
;;; UB4: A union of a unsigned int and a B4
UB4:    .union
b:      .tag B4                  
r:      .uint
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
rRunCount:      .tag UB4
        
bRSRV40:        .ubyte   ; reserved
bRSRV41:        .ubyte   ; reserved
bRSRV42:        .ubyte   ; reserved
bRSRV43:        .ubyte   ; reserved
IOThreadLen:   .endstruct
        
;;; LinuxThread: Everything needed for packet processing
LinuxThread:    .struct        
sTH:            .tag ThreadHeader ; sTH takes two regs
rCTRLAddress:   .uint             ; precompute PRUX_CTRL_ADDR
wResumeCount:   .ushort           ; Use resumes instead of CYCLEs for time base
wRSRV1:         .ushort           ; reserved
LinuxThreadLen: .endstruct     

;;; CT is the Current Thread!  It lives in R6-R13!
	.eval IOThreadLen/4, CTRegs
	.eval 6, CTBaseReg
	.asg R6, CTReg
CT:     .sassign CTReg, IOThread

LT:     .sassign CTReg, LinuxThread

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
	;int CSendVal(const char * str1, const char * str2, uint32_t val)
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

;;;;;;;;
;;;: macro sendValFromThread: Print a string and a value, with thread identified
;;;  INPUTS:
;;;    STR: First string to print
;;;    VAL: Value to print (reg or imm)
;;;  OUTPUTS: None
;;;  NOTES:
;;;  - WARNING: MUST NOT BE USED IN LEAF FUNCTIONS!
;;;  - TRASHES CALLER-SAVE REGS
	;int CSendFromThread(uint_32t prudir, const char * str, uint32_t val)
	.ref CSendFromThread
sendFromThread:        .macro STR, REGVAL
	.sect ".rodata:.string"
$M1?:  .cstring STR
	.text
	sub r2, r2, 2           ; Two bytes on stack
	sbbo &r3.w2, r2, 0, 2   ; Save current R3.w2
        mov r16, REGVAL         ; Get value to report before trashing anything else
        mov r14, CT.sTH.bID     ; First arg is prudir
        ldi32 r15, $M1?         ; Get string
        jal r3.w2, CSendFromThread 
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
;;;    Field DESTREG is cleared except its bottom bit is SRCREG[BITNUM]
;;;  NOTES:
;;;  - Note that supplying a register field -- e.g., r0.b0 -- for DSTREG
;;;    means that the rest of DSTREG remains unchanged!

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

;;;;;;;;
;;;: macro resumeTo: Context switch and continue at RESUMEADDR when next run
;;;  INPUTS: 
;;;  - RESUMEADDR: Label at which to continue execution 
;;;  OUTPUTS: NONE
;;;  NOTES:
;;;  - Slightly faster than suspendThread but uses more instruction space
resumeTo:       .macro RESUMEADDR
        ldi CT.sTH.wResAddr,$CODE(RESUMEADDR) ; Set our resume point
	resumeAgain                           ; And resume to that point
	.endm

;;;;;;;;
;;;: macro saveResumePoint: Jump to RESUMEADDR when current thread is resumed
;;;  INPUTS: 
;;;  - RESUMEADDR: Label at which to continue execution 
;;;  OUTPUTS: NONE
;;;  NOTES:
;;;  - Slightly faster than suspendThread but uses more instruction space
saveResumePoint:       .macro RESUMEADDR
        ldi CT.sTH.wResAddr,$CODE(RESUMEADDR) ; Set our resume point
	saveThisThread                        ; And save current state
	.endm

;;;;;;;;
;;;: macro resumeAgain: Context switch and continue at same place as last time
;;;  INPUTS: NONE
;;;  OUTPUTS: NONE
;;;  NOTES:
;;;  - Currently fastest context switch if current thread must be save but looping to same spot
resumeAgain:       .macro
        saveThisThread                        ; Stash
        loadNextThread                        ; Load next guy
        jmp CT.sTH.wResAddr                   ; Resume him
	.endm

;;;;;;;;
;;;: macro resumeNextThread: Load and continue next thread without saving current
;;;  INPUTS: NONE
;;;  OUTPUTS: NONE
;;;  NOTES:
;;;  - Currently fastest context switch if looping to same spot
resumeNextThread:       .macro
        loadNextThread                        ; Load next guy
        jmp CT.sTH.wResAddr                   ; Resume him
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

;;; RX Watcher thread runner: Report on changing RX bits
rxr0:   sendVal PRUX_STR,"""CT""",CT.rRunCount.r ; Report counter value
rxr1:   suspendThread                            ; Now context switch
RXWatcherThreadRunner:
        loadBit r0.b0, r31, CT.bRXRDYPin ; read pin to b0
	qbeq rxwr1, r0.b0, CT.bRSRV40    ; check if b0 has changed
        mov CT.bRSRV40, r0.b0            ; update if so
	mov r0.b3, CT.sTH.bID            ; id in top byte
	mov r0.w1, CT.bRXRDYPin          ; 0 then pin # in next two bytes
        sendVal PRUX_STR,"""RY""",r0     ; Report prudir and new value
rxwr1:  
        loadBit r0.b0, r31, CT.bRXDATPin
	qbeq rxwr2, r0.b0, CT.bRSRV41
        mov CT.bRSRV41, r0.b0
	mov r0.b3, CT.sTH.bID 
	mov r0.w1, CT.bRXDATPin
        sendVal PRUX_STR,"""DT""",r0 ; Report prudir and new value
rxwr2:  
	add CT.rRunCount.r, CT.rRunCount.r, 1 ; Increment run count
	lsl r0, CT.rRunCount.r, 5       ; Keep low order 27 bits
	qbeq rxr0, r0, 0           ; Report in if they're all zero
        jmp rxr1                   ; Either way then sleep

	
;;; Interclocking thread runner: Report every N shared ticks
;;; This version forces a context switch after each edge
;;; and seems to show about 1.47Mbps x 6 free-running
InterClockThreadRunner:
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
        add CT.rRunCount.r, CT.rRunCount.r, 1 ; Increment shared clock count
	lsl r0, CT.rRunCount.r, 6           ; Keep low order 26 bits
	qbne ictr4, r0, 0                 ; Jump ahead if not zero
	.ref pruDirData
	ldi r28, $sizeof(PruDirBuffers)   ; First operand to multiply
	mov r29, CT.sTH.bID               ; Second operand to multiply
        ldi r1, pruDirData + PruDirBuffers.in + InboundPacketBuffer.written ; Set up base address in multiply delay slot
        xin 0, &r26, 4                    ; Read 32 bit multiplication result
        add r0,r1,r26                     ; Add to base address
        lsr r1, CT.rRunCount.r, 28        ; Get left four bits of count
        sbbo &r1, r0, 0, 1                ; Stash in pruDirData.pruDirBuffers[prudir].in.written
        sendFromThread """CT""",CT.rRunCount.r ; Report counter value
;        sendFromThread """CA""",r0 ; Report computed address
ictr4:  saveResumePoint ictr6
	
	;; Our clock high loop
ictr5:  resumeNextThread                 ; To wait, or wait more, after rising edge
ictr6:  .if ON_PRU == 0 
          qbbs ictr5, r31, CT.bRXRDYPin  ; PRU0 is MATCHER: if me 1, you 1, we're good
        .else                            ; ON_PRU == 1
	  qbbc ictr5, r31, CT.bRXRDYPin  ; PRU1 is MISMATCHER: if me 1, you 0, we're good
        .endif  
        jmp ictr1               

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
	
	;; Init threads by hand
        initThis 0*CTRegs, IOThreadLen, 0, InterClockThreadRunner ; Thread ID 0 at shift 0
        initNext 1*CTRegs, IOThreadLen             ; Info for thread 1
        saveThisThread                             ; Stash thread 0
	
        initThis 1*CTRegs, IOThreadLen, 1, InterClockThreadRunner ; Thread ID 1 at shift CTRegs
	initNext 2*CTRegs, IOThreadLen             ; Info for thread 2
        saveThisThread                             ; Stash thread 1
	
        initThis 2*CTRegs, IOThreadLen, 2, InterClockThreadRunner ; Thread ID 2 at shift 2*CTRegs
	initNext 3*CTRegs, LinuxThreadLen          ; Info for thread 3
        saveThisThread                             ; Stash thread 2
	
        initThis 3*CTRegs, LinuxThreadLen, 3, LinuxThreadRunner ; Thread ID 3 at shift 3*CTRegs
	ldi32 LT.rCTRLAddress, PRUX_CTRL_ADDR      ; Precompute per-PRU CTRL regs base address
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
	
        exitFunc 6              ; Done

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

;; 	;; unsigned processOutboundITCPacket(uint8_t * packet, uint16_t len);
;; 	;; R14: packet
;;         ;; R15: len
;;         .def processOutboundITCPacket
;; processOutboundITCPacket:
;;         qbne hasLen, r15, 0
;;         ldi r14, 0
;;         jmp r3.w2               ; Return 0
;; hasLen:
;;         lbbo &r15, r14, 0, 1    ; R15 = packet[0]
;;         add r15, r15, 3         ; Add 3 to show we were here
;;         sbbo &r15, r14, 0, 1    ; packet[0] = R15
;;         ldi r14, 1
;;         jmp r3.w2               ; Return 1
        
