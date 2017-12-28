;;;;;;
;;; MACRO DEFINITIONS
	
;        .asg 1, DEBUG_TAGS
        .asg 0, DEBUG_TAGS

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
	saveRegs 2              ; Save current R3.w2
        mov r16, REGVAL         ; Get value to report before trashing anything else
        ldi32 r14, $M1?         ; Get string1
        ldi32 r15, $M2?         ; Get string2
        jal r3.w2, CSendVal     ; Call CSendVal (ignore return)
	restoreRegs 2           ; Restore r3.w2 
        .endm

;;;;;;;;
;;;: macro sendFromThread: Print a string and a value, with thread identified
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
	saveRegs 2              ; Save current R3.w2
        mov r16, REGVAL         ; Get value to report before trashing anything else
        mov r14, CT.sTH.bID     ; First arg is prudir
        ldi32 r15, $M1?         ; Get string
        jal r3.w2, CSendFromThread 
	restoreRegs 2           ; Restore r3.w2 
        .endm

;;;;;;;;
;;;: macro startTagBurst: Set up to print tags for next NCYCLES rising edges
;;;  INPUTS:
;;;   NCYCLES: Number of rising edges to report for 1..255
;;;   WHICH: I to report input events, or O to report output events
;;;  OUTPUTS: None
;;;  NOTES:
;;;  - ALTERS runCount non-monotonically
startTagBurst:        .macro NCYCLES, WHICH
	analyzeReportFlags WHICH
        or CT.sTH.bFlags, CT.sTH.bFlags, (1<<FLAG)|(1<<PacketRunnerFlags.fTagBurst) ; set flags
	ldi CT.rRunCount.b.b0, 256-NCYCLES ; set runCount.b0 to hit zero after NCYCLES increments
        .endm
	
startITagBurst:        .macro NCYCLES
        startTagBurst NCYCLES, 0
        .endm
	
startOTagBurst:        .macro NCYCLES
        startTagBurst NCYCLES, 1
        .endm
        
analyzeReportFlags:     .macro WHICH
        .if (WHICH == 0)
        .eval PacketRunnerFlags.fReportITags, FLAG
	.elseif (WHICH == 1)
        .eval PacketRunnerFlags.fReportOTags, FLAG
	.else
        .emsg "WHICH must be 0 or 1, not ':WHICH:'"
        .endif
        .endm
	
;;;;;;;
;;;: macro sendITag: Maybe print an input-related tag string plus the PC, with thread identified
sendITag:        .macro STR, REGVAL
        sendTag STR, 0, REGVAL
	.endm
;;;;;;;
;;;: macro sendOTag: Maybe print an output-related tag string plus the PC, with thread identified
sendOTag:        .macro STR, REGVAL
        sendTag STR, 1, REGVAL
	.endm


;;;;;;;;
;;;: macro sendTag: Maybe print a tag string plus the PC, with thread identified
;;;  INPUTS:
;;;    STR: Tag to print
;;;    WHICH: Reporting context: 0 for input or 1 for output
;;;  OUTPUTS: None
;;;  NOTES:
;;;  - Does nothing (except cost one cycle) unless CT.sTH.bFlags has an appropriate
;;;	PacketRunnerFlags.fReportXTags set
	;int CSendTagFromThread(uint_32t prudir, const char * str, uint32_t pc)
	.ref CSendTagFromThread
sendTag:        .macro STR, WHICH, REGVAL
	.if DEBUG_TAGS != 0
	.sect ".rodata:.string"
$M1?:  .cstring STR
	.text
	analyzeReportFlags WHICH
	qbbc $M3?, CT.sTH.bFlags, FLAG                        ; Jump out if not reporting appropriate tags
	qbbc $M0?, CT.sTH.bFlags, PacketRunnerFlags.fTagBurst ; Jump ahead if not burst processing
	qbne $M0?, CT.rRunCount.b.b0, 0 ; Jump ahead if burst isn't done
        and CT.sTH.bFlags, CT.sTH.bFlags, 0xff&~((1<<PacketRunnerFlags.fReportITags)|(1<<PacketRunnerFlags.fReportOTags)|(1<<PacketRunnerFlags.fTagBurst)) ; clear flags
$M0?:	saveRegs 2              ; Save current R3.w2
        mov r14, CT.sTH.bID     ; First arg is prudir
        ldi32 r15, $M1?         ; Get string
;$M2?:   ldi r16, $CODE($M2?)    ; Get current iram to identify call
	mov r16.w0, REGVAL      ; Take bottom 16 bits of supplied val
        jal r3.w2, CSendTagFromThread 
	restoreRegs 2           ; Restore r3.w2 
$M3?:                           ; Done
	.endif
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
	saveRegs BYTES
        .endm

;;;;;;;;
;;;: macro saveRegs: Standard register save macro
;;;  INPUTS:
;;;    BYTES: Number of bytes to save on stack, starting with r3.w2
;;;  OUTPUTS: NONE
;;;  - BYTES can be 0 or 2+
saveRegs:      .macro BYTES
        .if BYTES > 0
        sub r2, r2, BYTES
        sbbo &r3.w2, r2, 0, BYTES
        .endif
        .endm

;;;;;;;;
;;;: macro restoreRegs: Standard register restore macro
;;;  INPUTS:
;;;    BYTES: Number of bytes to restore from stack, starting with r3.w2
;;;  OUTPUTS: NONE
;;;  NOTES:
;;;  - BYTES better damn match that in the associated saveRegs
restoreRegs:      .macro BYTES
	.if BYTES > 0
        lbbo &r3.w2, r2, 0, BYTES ; Restore regs
        add r2, r2, BYTES         ; Pop stack
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
	restoreRegs BYTES       ; Restore regs
        jmp r3.w2               ; And return
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
                
