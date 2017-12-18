	.cdecls "prux.h"
	
	;; STRUCTURE DECLARATIONS

;;; Demo struct: STATE_INFO
STATE_INFO:     .struct
RXRDY_COUNT:    .ubyte
RXDAT_COUNT:    .ubyte
RXRDY_STATE:    .ubyte
RXDAT_STATE:    .ubyte
STATE_INFO_LEN: .endstruct
	
LiveCounts:     .sassign R5, STATE_INFO
        
;;; ThreadCoord: A length (in bytes) and an offset (in registers)
ThreadCoord:      .struct
bOffsetRegs:    .ubyte      ; offset in registers  (to load in r0.b0)
bLenBytes:      .ubyte      ; length in bytes      (to load in r0.b1)
ThreadCoord_LEN:  .endstruct

;;; ThreadLoc: A union of a ThreadCoord and a word to load
ThreadLoc:      .union
sTC:    .tag ThreadCoord
w:      .ushort                     
        .endunion

;;; ThreadHeader: Enough info to save, load, and context switch a thread
ThreadHeader:   .struct
sTHIS:          .tag ThreadLoc  ; Our thread storage location
sNEXT:          .tag ThreadLoc  ; Next guy's storage location
	
bID:            .ubyte  ; thread id (prudir for 0..2, 3 for linux)
bFLAGS:         .ubyte  ; flags
wRES_ADDR:      .ushort ; Resume address after context switch	
ThreadHeader_LEN:       .endstruct

;;; IOThread: Everything needed for a prudir state machine
IOThread:       .struct
sTH:            .tag ThreadHeader ; sTH takes two regs

bTXRDY_PN:      .ubyte  ; Transmit Ready R30 Pin Number
bTXDAT_PN:      .ubyte  ; Transmit Data  R30 Pin Number
bRXRDY_PN:      .ubyte  ; Receive Ready  R31 Pin Number
bRXDAT_PN:      .ubyte  ; Receive Data   R31 Pin Number

bOUTDATA:       .ubyte  ; current bits being shifted out
bOUTBCNT:       .ubyte  ; count of bits remaining to shift out
bINPDATA:       .ubyte  ; current bits being shifted in
bINPBCNT:       .ubyte  ; count of bits remaining to shift in

bPREVOUT:       .ubyte  ; last bit sent 
bTHISOUT:       .ubyte  ; current bit to sent
bOUT1CNT:       .ubyte  ; current count of output 1s sent
bINP1CNT:       .ubyte  ; current count of input 1s received

rTXDAT_MASK:    .uint   ; 1<<TXDAT_PN
rRSRV3:         .uint   ; reserved
rRSRV4:         .uint   ; reserved
IOThread_LEN:   .endstruct
        
;;; LinuxThread: Everything needed for packet processing
LinuxThread:    .struct        
sTH:            .tag ThreadHeader ; sTH takes two regs
LinuxThread_LEN: .endstruct     

;;; CT is the Current Thread!  It lives in R6-R13!
	.eval IOThread_LEN/4, CTRegs
	.eval 6, CTBaseReg
	.asg R6, CTReg
CT:     .sassign CTReg, IOThread

	;int sendVal(const char * str, uint32_t val)
	.ref sendVal            

        
;;;;;;;;
;;;: macro SENDVAL: Print two strings and a value
;;;  INPUTS:
;;;    STR1: First string to print
;;;    STR2: Second string to print
;;;    VAL: Value to print (reg or imm)
;;;  OUTPUTS: None
;;;  NOTES:
;;;  - WARNING: MUST NOT BE USED IN LEAF FUNCTIONS!
;;;  - TRASHES CALLER-SAVE REGS

SENDVAL:        .macro STR1, STR2, REGVAL
	.sect ".rodata:.string"
$M1?:  .cstring STR1
$M2?:  .cstring STR2
	.text
	SUB R2, R2, 2           ; Two bytes on stack
	SBBO &R3.w2, R2, 0, 2   ; Save current R3.w2
        MOV R16, REGVAL         ; Get value to report before trashing anything else
        LDI32 R14, $M1?         ; Get string1
        LDI32 R15, $M2?         ; Get string2
        JAL R3.w2, sendVal      ; Call sendVal (ignore return)
	LBBO &R3.w2, R2, 0, 2   ; Restore R3.w2 
        ADD R2, R2, 2           ; Pop stack
        .endm

;;;;;;;;;
;;;: macro LOADBIT: Copy SRCREG bit BITNUM to bottom of DESTREG
;;;  INPUTS:
;;;    SRCREG: Source register field; REG
;;;    BITNUM: Number of bit (0 == LSB) to copy; OP(31)
;;;    DSTREG: Destination register field; REG
;;;  OUTPUTS:
;;;    DESTREG is cleared except its bottom bit is SRCREG[BITNUM]
LOADBIT:        .macro DESTREG, SRCREG, BITNUM
        LSR DESTREG, SRCREG, BITNUM ; Position desired bit at bottom of destreg
        AND DESTREG, DESTREG, 1     ; Flush the rest
        .endm

;;;;;;;;
;;;: macro ENTERFUNC: Function prologue
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

;;;;;;;;
;;;: macro EXITFUNC: Function epilogue
;;;  INPUTS:
;;;    BYTES: Number of bytes to restore from stack, starting with
;;;r3.w2
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


INITTHIS: .macro THISSHIFT,THISBYTES,ID,RESUMEADDR
        ZERO &CT,IOThread_LEN                      ; Clear CT to start
        LDI CT.sTH.sTHIS.sTC.bOffsetRegs, THISSHIFT
        LDI CT.sTH.sTHIS.sTC.bLenBytes, THISBYTES
        LDI CT.sTH.bID, ID
        LDI CT.sTH.bFLAGS, 0
	LDI CT.sTH.wRES_ADDR,$CODE(RESUMEADDR)
	.endm

INITNEXT:  .macro NEXTSHIFT,NEXTBYTES
	LDI CT.sTH.sNEXT.sTC.bOffsetRegs, NEXTSHIFT
        LDI CT.sTH.sNEXT.sTC.bLenBytes, NEXTBYTES
        .endm

SAVETHISTHREAD: .macro
        mov r0.w0, CT.sTH.sTHIS.w  ; r0.b0 <- this bOffsetRegs, r0.b1 <- this bLenBytes
        xout PRUX_SCRATCH, &CT, b1 ; store this thread
        .endm

LOADNEXTTHREAD: .macro
        mov r0.w0, CT.sTH.sNEXT.w ; r0.b0 <- next bOffsetRegs, r0.b1 <- next bLenBytes
        xin PRUX_SCRATCH, &CT, b1 ; load next thread
        .endm

;;;;;;;;;;;;;;;
;;; SCHEDULER

;;;;;;;;
;;;: target contextSwitch: Switch to next thread
contextSwitch:
        SAVETHISTHREAD
        ;; FALL THROUGH
;;;;;;;;
;;;: target nextContext: Load next thread and resume it
nextContext:
	LOADNEXTTHREAD              ; Pull in next thread
        jmp CT.sTH.wRES_ADDR    ; and resume it
                

;;;;;;;;
;;;: macro SUSPEND_THREAD: Sleep current thread
;;;  INPUTS: NONE
;;;  OUTPUTS: NONE
;;;  NOTES:
;;;  - Generates an arbitrary delay (of 30ns or more)
;;;  - Trashes everything but R2, R3.w2, and CT
SUSPEND_THREAD: .macro
        jal CT.sTH.wRES_ADDR, contextSwitch
        .endm
                

;;; LINUX thread runner 
LinuxThreadRunner:
        JAL R3.w2, processPackets ; Surface to C level, check for linux action
        SUSPEND_THREAD            ; Then context switch
        JMP LinuxThreadRunner     ; Then try again

;;; Idle thread runner 
IdleThreadRunner:
        SUSPEND_THREAD          ; Just context switch
        JMP IdleThreadRunner    ; Then try again


;;; Timing thread runner: Sends a 'timer' packet every 128M iterations
ttr0:   SENDVAL PRUX_STR,""" timer """,CT.rRSRV3 ; Report counter value
ttr1:   SUSPEND_THREAD          ; Now context switch
TimingThreadRunner:
	ADD CT.rRSRV3, CT.rRSRV3, 1 ; Increment secret counter
	LSL R0, CT.rRSRV3, 5       ; Keep low order 27 bits
	QBEQ ttr0, R0, 0           ; Report in if they're all zero
        JMP ttr1                   ; Either way then sleep


        .text
        .def mainLoop
mainLoop:
	SUB R2, R2, 6           ; Get six bytes on stack
        SBBO &R3.w2, R2, 0, 6   ; Store R3.w2 and R4 on stack

        SENDVAL PRUX_STR,""" entering main loop""",R2 ; Say hi
	.ref processPackets
l0:     
        JAL R3.w2, processPackets ; Return == 0 if firstPacket done
	QBNE l0, R14, 0           ; Wait for that before initting state machines
	JAL R3.w2, startStateMachines ; Not expected to return
	
        SENDVAL PRUX_STR,""" unexpected return to main loop""",R2 ; Say bye
	LBBO &R3.w2, R2, 0, 6   ; Restore R3.w2 and R4
        ADD R2, R2, 6           ; Pop stack
        JMP r3.w2               ; Return

        .text
        .def addfuncasm
addfuncasm:
	SUB R2, R2, 6           ; Get six bytes on stack
        SBBO &R3.w2, R2, 0, 6   ; Store R3.w2 and R4 on stack
        ADD R4, R15, R14        ; Compute function, result to R4
	SENDVAL PRUX_STR,""" addfuncasm sum""",R4 ; Report it
        LBBO &R3.w2, R2, 0, 6   ; Restore R3.w2 and R4
        ADD R2, R2, 6           ; Pop stack
        JMP r3.w2               ; Return
        
startStateMachines:
	ENTERFUNC 2
        ;; DEMO CODE INIT
	;; Clear counts
	ZERO &LiveCounts,STATE_INFO_LEN
        ;; Read initial pin states
	LOADBIT LiveCounts.RXRDY_STATE, r31, PRUDIR1_RXRDY_R31_BIT  ; pru0 SE, pru1 NW
	LOADBIT LiveCounts.RXDAT_STATE, r31, PRUDIR1_RXDAT_R31_BIT  ; pru0 SE, pru1 NW
        ;; END DEMO CODE INIT
	
	;; Init threads by hand
        INITTHIS 0*CTRegs, IOThread_LEN, 0, IdleThreadRunner ; Thread ID 0 at shift 0
        INITNEXT 1*CTRegs, IOThread_LEN            ; Info for thread 1
        SAVETHISTHREAD                             ; Stash thread 0
	
        INITTHIS 1*CTRegs, IOThread_LEN, 1, TimingThreadRunner ; Thread ID 1 at shift CTRegs
	INITNEXT 2*CTRegs, IOThread_LEN            ; Info for thread 2
        SAVETHISTHREAD                             ; Stash thread 1
	
        INITTHIS 2*CTRegs, IOThread_LEN, 2, IdleThreadRunner ; Thread ID 2 at shift 2*CTRegs
	INITNEXT 3*CTRegs, LinuxThread_LEN         ; Info for thread 3
        SAVETHISTHREAD                             ; Stash thread 2
	
        INITTHIS 3*CTRegs, LinuxThread_LEN, 3,LinuxThreadRunner ; Thread ID 3 at shift 3*CTRegs
        INITNEXT 0*CTRegs, IOThread_LEN            ; Next is back to thread 0
        SAVETHISTHREAD                             ; Stash thread 3
        ;; Done with by-hand thread inits

        ;; Report in             
        SENDVAL PRUX_STR,""" Releasing the hounds""", CT.sTH.wRES_ADDR ; Report in

;; l99:
;;         jal r3.w2, processPackets
;;         jmp l99

        ;; Thread 3 is still loaded
        JMP CT.sTH.wRES_ADDR    ; Resume it
	EXITFUNC 2

        .def advanceStateMachines
advanceStateMachines:
	ENTERFUNC 6             ; Save R3.w2 and R4 on stack
	
	LOADBIT r4, r31, 2     ; rxrdy (r31.t2) to r4
        QBEQ asm1, r4, LiveCounts.RXRDY_STATE ; jump if no change
	MOV LiveCounts.RXRDY_STATE, r4        ; else update retained state,
        ADD LiveCounts.RXRDY_COUNT, LiveCounts.RXRDY_COUNT, 1 ; increment, and
	SENDVAL PRUX_STR,""" RXRDY""",LiveCounts.RXRDY_COUNT ; report change

asm1:
        LOADBIT r4, r31, 14    ; rxdat (r31.t14) to r4
        QBEQ asm2, r4, LiveCounts.RXDAT_STATE ; jump if no change
	MOV LiveCounts.RXDAT_STATE, r4        ; else update retained state
        ADD LiveCounts.RXDAT_COUNT, LiveCounts.RXDAT_COUNT, 1 ; increment, and
	SENDVAL PRUX_STR,""" RXDAT""",LiveCounts.RXDAT_COUNT ; report change

asm2:   EXITFUNC 6              ; Done

	;; void copyOutScratchPad(uint8_t * packet, uint16_t len)
        ;; R14: ptr to destination start
        ;; R15: bytes to copy
        ;; R17: index
        .def copyOutScratchPad
copyOutScratchPad:
        ;; NON-STANDARD PROLOGUE
	SUB R2, R2, 8           ; Get room for first two regs of CT
        SBBO &R6, R2, 0, 8      ; Store R6 & R7 on stack
	SBBO &R7, R14, 1, 1     ; Store ID at packet[1]
	LSR R7, R7, 16          ; Right justify resume address
	SBBO &R7, R14, 2, 2     ; Store resume address at packet[2..3]
	ADD R14, R14, 4         ; Move up to start of scratchpad save area
        SUB R15, R15, 4         ; Adjust for room we used

        LDI R17,0               ; index = 0
        MIN R15, R15, 4*30      ; can the xfr shift, itself, wrap?
cosp1:
	QBGE cosp2, R15, R17     ; Done when idx reaches len
	LSR R0.b0, R17, 2        ; Get reg of byte: at idx/4
	XIN PRUX_SCRATCH, &R6, 4 ; Scratchpad to R6, shifted 
	AND R0.b0, R17, 3        ; Get byte within reg at idx % 4
	LSL R0.b0, R0.b0, 3      ; b0 = (idx%4)*8
	LSR R6,R6,R0.b0          ; CT >>= b0
	SBBO &R6, R14, R17, 1    ; Stash next byte at R14[R17]
        ADD R17, R17, 1          ; One more byte to shift bits after
        JMP cosp1
cosp2:
        ;; NON-STANDARD EPILOGUE
        LBBO &R6, R2, 0, 8      ; Restore R6 and R7
        ADD R2, R2, 8           ; Pop stack
        JMP r3.w2               ; Return

	;; unsigned processOutboundITCPacket(uint8_t * packet, uint16_t len);
	;; R14: packet
        ;; R15: len
        .def processOutboundITCPacket
processOutboundITCPacket:
        QBNE hasLen, r15, 0
        LDI R14, 0
        JMP r3.w2               ; Return 0
hasLen:
        LBBO &R15, R14, 0, 1    ; R15 = packet[0]
        ADD R15, R15, 3         ; Add 3 to show we were here
        SBBO &R15, R14, 0, 1    ; packet[0] = R15
        LDI R14, 1
        JMP r3.w2               ; Return 1
        
