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
bOutBCnt:       .ubyte  ; count of bits already shifted out
bInpData:       .ubyte  ; current bits being shifted in
bInpBCnt:       .ubyte  ; count of bits already shifted in

bRSRV0:         .ubyte  ; reserved
bRSRV1:         .ubyte  ; reserved
bOut1Cnt:       .ubyte  ; current count of output 1s sent
bInp1Cnt:       .ubyte  ; current count of input 1s received

rTXDATMask:     .uint   ; 1<<TXDAT_PN
rRunCount:      .tag UB4
        
bInpByte:       .ubyte   ; bytes already written of inbound packet
bOutByte:       .ubyte   ; bytes already read from outbound packet
bOutLen:        .ubyte   ; length in bytes of outbound packet
bRSRV43:        .ubyte   ; reserved
IOThreadLen:   .endstruct

PacketRunnerFlags:  .enum
fPacketSync:    .emember 0
fOutputStuffed: .emember 1
fReportTags:    .emember 2
fFlagRsrv3:     .emember 3
fFlagRsrv4:     .emember 4
fFlagRsrv5:     .emember 5
fFlagRsrv6:     .emember 6
fFlagRsrv7:     .emember 7
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

