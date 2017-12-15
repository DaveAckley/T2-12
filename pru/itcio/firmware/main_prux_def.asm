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
        
;;; IOThread: Everything needed for a prudir state machine
IOThread:       .struct
bTHIS_ID:       .ubyte   ; this context id (0..2)
bNEXT_ID:       .ubyte   ; next context id (0..2)
bPREV_ID:       .ubyte   ; prev context id (0..2)
bFLAGS:         .ubyte   ; flags

bTXRDY_PN:      .ubyte  ; Transmit Ready R30 Pin Number
bTXDAT_PN:      .ubyte  ; Transmit Data  R30 Pin Number
bRXRDY_PN:      .ubyte  ; Receive Ready  R31 Pin Number
bRXDAT_PN:      .ubyte  ; Receive Data   R31 Pin Number

wRES_ADDR:      .ushort ; Resume address after context switch
bOUT1CNT:       .ubyte  ; current count of output 1s sent
bINP1CNT:       .ubyte  ; current count of input 1s received

bOUTDATA:       .ubyte  ; current bits being shifted out
bOUTBCNT:       .ubyte  ; count of bits remaining to shift out
bINPDATA:       .ubyte  ; current bits being shifted in
bINPBCNT:       .ubyte  ; count of bits remaining to shift in

bPREVOUT:       .ubyte  ; last bit sent 
bTHISOUT:       .ubyte  ; current bit to sent
wRSRV2:         .ushort ; reserved

rTXDAT_MASK:    .uint   ; 1<<TXDAT_PN
rRSRV3:         .uint   ; reserved
rRSRV4:         .uint   ; reserved
IOThread_LEN:   .endstruct
        
;;; CT is the Current Thread!  It lives in R6-R13!
CT:     .sassign R6, IOThread
	


	;int sendVal(const char * str, uint32_t val)
	.ref sendVal            
		
SENDVAL:        .macro STR, REGVAL
	.sect ".rodata:.string"
$MSG?:  .cstring STR
	.text
        LDI32 R14, $MSG?        ; Get string
        MOV R15, REGVAL         ; And value to report
        JAL R3.w2, sendVal      ; Call sendVal (ignore return)
        .endm

LOADBIT:        .macro DESTREG, SRCREG, BITNUM
        LSR DESTREG, SRCREG, BITNUM ; Position desired bit at bottom of destreg
        AND DESTREG, DESTREG, 1     ; Flush the rest
        .endm

	.text
        .def mainLoop
mainLoop:
	JAL R3.w2, initStateMachines
l1:     JAL R3.w2, advanceStateMachines
	.ref processPackets
        JAL R3.w2, processPackets
        jmp l1
	
        .text
        .def addfuncasm
addfuncasm:
	SUB R2, R2, 6           ; Get six bytes on stack
        SBBO &R3.w2, R2, 0, 6   ; Store R3.w2 and R4 on stack
        ADD R4, R15, R14        ; Compute function, result to R4
	MOV R15, R4             ; Get value to report
;	LDI32 R15, 0x56789abc   
	SENDVAL """first char to send to the moon alice""",R15 ; Report it
	MOV R14, R4             ; Get return value
        LBBO &R3.w2, R2, 0, 6   ; Restore R3.w2 and R4
        ADD R2, R2, 6           ; Pop stack
        JMP r3.w2               ; Return
        
        
        .def initStateMachines
initStateMachines:
	;; Clear counts
	ZERO &LiveCounts,STATE_INFO_LEN
	
        ;; Read initial pin states
	LOADBIT LiveCounts.RXRDY_STATE, r31, PRUDIR1_RXRDY_R31_BIT  ; pru0 SE, pru1 NW
	LOADBIT LiveCounts.RXDAT_STATE, r31, PRUDIR1_RXDAT_R31_BIT  ; pru0 SE, pru1 NW
        JMP r3.w2               ; Return

        .def advanceStateMachines
advanceStateMachines:
	SUB R2, R2, 6           ; Get six bytes on stack
        SBBO &R3.w2, R2, 0, 6   ; Store R3.w2 and R4 on stack
	
	LOADBIT r4, r31, 2     ; rxrdy (r31.t2) to r4
        QBEQ asm1, r4, LiveCounts.RXRDY_STATE ; jump if no change
	MOV LiveCounts.RXRDY_STATE, r4        ; else update retained state,
        ADD LiveCounts.RXRDY_COUNT, LiveCounts.RXRDY_COUNT, 1 ; increment, and
	SENDVAL """RXRDY""",LiveCounts.RXRDY_COUNT           ; report change

asm1:
        LOADBIT r4, r31, 14    ; rxdat (r31.t14) to r4
        QBEQ asm2, r4, LiveCounts.RXDAT_STATE ; jump if no change
	MOV LiveCounts.RXDAT_STATE, r4        ; else update retained state
        ADD LiveCounts.RXDAT_COUNT, LiveCounts.RXDAT_COUNT, 1 ; increment, and
	SENDVAL """RXDAT""",LiveCounts.RXDAT_COUNT           ; report change

asm2:
	LBBO &R3.w2, R2, 0, 6   ; Restore R3.w2 and R4
        ADD R2, R2, 6           ; Pop stack
        JMP r3.w2               ; Return
	

	;; unsigned processITCPacket(uint8_t * packet, uint16_t len);
	;; R14: packet
        ;; R15: len
        .def processITCPacket
processITCPacket:
        QBNE hasLen, r15, 0
        LDI R14, 0
        JMP r3.w2               ; Return 0
hasLen:
        LBBO &R15, R14, 0, 1    ; R15 = packet[0]
        ADD R15, R15, 3         ; Add 3 to show we were here
        SBBO &R15, R14, 0, 1    ; packet[0] = R15
        LDI R14, 1
        JMP r3.w2               ; Return 1
        
