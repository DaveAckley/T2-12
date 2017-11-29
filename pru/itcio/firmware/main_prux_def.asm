	.cdecls "prux.h"
	
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

        .text
        .def addfuncasm
addfuncasm:
	SUB R2, R2, 6           ; Get six bytes on stack
        SBBO &R3.w2, R2, 0, 6   ; Store R3.w2 and R4 on stack
        ADD R4, R15, R14        ; Compute function, result to R4
;	MOV R15, R4             ; Get value to report
	LDI32 R15, 0x56789abc                                  
	SENDVAL """first char to send to the moon alice""",R15 ; Report it
	MOV R14, R4             ; Get return value
        LBBO &R3.w2, R2, 0, 6   ; Restore R3.w2 and R4
        ADD R2, R2, 6           ; Pop stack
        JMP r3.w2               ; Return
        
        
        .def initStateMachines
initStateMachines:
        JMP r3.w2               ; Return

        .def advanceStateMachines
advanceStateMachines:
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
        
