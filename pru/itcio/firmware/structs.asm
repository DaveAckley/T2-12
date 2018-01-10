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
	
bID:            .ubyte          ; prudir 0..2, 3 for linux
bFlags:         .ubyte          ; flags

wResAddr:       .ushort ; Resume address after context switch	
ThreadHeaderLen:       .endstruct

;;; IOThread: Everything needed for a prudir state machine
IOThread:       .struct
sTH:            .tag ThreadHeader ; sTH takes two regs CT, CT+1
;;; CT+2
bTXRDYPin:      .ubyte  ; Transmit Ready R30 Pin Number
bTXDATPin:      .ubyte  ; Transmit Data  R30 Pin Number
bRXRDYPin:      .ubyte  ; Receive Ready  R31 Pin Number
bRXDATPin:      .ubyte  ; Receive Data   R31 Pin Number
;;; CT+3
bOutData:       .ubyte  ; current bits being shifted out
bOutBNum:       .ubyte  ; next bit number (0=LSB) to shift out
bOutByte:       .ubyte   ; bytes already read from outbound packet
bOutLen:        .ubyte   ; length in bytes of outbound packet
;;; CT+4
bInpData:       .ubyte  ; current bits being shifted in
bInpBNum:       .ubyte  ; next bit number (0=LSB) to shift in
wInpByte:       .ushort  ; bytes already written of inbound packet
;;; CT+5
bOut1Cnt:       .ubyte  ; current count of output 1s sent
bInp1Cnt:       .ubyte  ; current count of input 1s received
wRSRV2:         .ushort
;;; CT+6
rRunCount:      .tag UB4
;;; CT+7
rBufAddr:       .uint ; base address of our struct PruDirBuffers
        
IOThreadLen:   .endstruct

PacketRunnerFlags:  .enum
fPacketSync:    .emember 0      ; True if good packet delimiter has been seen
fByteStuffed:   .emember 1      ; True if this output byte should be bitstuffed
fStuffThisBit:  .emember 2      ; True if we need to stuff a zero now regardless of fByteStuffed
fReportITags:   .emember 3      ; True if reporting input tag events
fReportOTags:   .emember 4      ; True if reporting output tag events
fTagBurst:      .emember 5      ; True if inside a self-delimiting burst of tag reporting
fRSRV6:         .emember 6      ; reserved
fRSRV7:         .emember 7      ; reserved
                .endenum
        
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

;;; CheckDirs: A byte for outbound and a byte for inbound dirs to check
CheckDirs:      .struct
bCheckOut:       .ubyte      ; check for outbound packet if bOutDirs[prudir]
bCheckIn:        .ubyte      ; check for inbound space if bInDirs[prudir]
CheckDirsLen:  .endstruct

;;; CheckU
CheckU:     .union
sCD:    .tag CheckDirs
w:      .ushort
        .endunion

;;; PSSStruct: One reg for state shared within each PRU
PSSStruct:      .struct
sCU:            .tag CheckU
wRSRV1:         .ushort          ; reserved
PSSStructLen:   .endstruct     

;;; PSS is PRU-wide Shared State!  It lives in R5
        .asg R5, PSSReg
PSS:    .sassign PSSReg, PSSStruct
        
