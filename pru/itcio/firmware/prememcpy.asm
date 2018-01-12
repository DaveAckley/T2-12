;;; prememcpy.asm: memcpy that prepends a single byte
;;; Modified by ackley from memcpy.asm by TI (see copyright info at bottom of file)

        .asg r14, to
        .asg r15, from
        .asg r16, size          ; arg3: size including 1 from arg4 + arg3-1 from from
        .asg r17, to_tmp        ; arg4: byte to prepend, then temporary
        .asg 48, max_size
        .asg r18, tmp

;;; void * prememcpy(void * to, void * from, unsigned size, unsigned firstbyte)
;;; writes to 'to' firstbyte followed by length-1 bytes read from 'from'.
;;; returns 'to'.

        .text
        .global prememcpy
prememcpy:
        qbeq return, size, 0    ; quick exit if no size
	mov tmp.b0, to_tmp      ; Save byte to prepend
        mov to_tmp, to          ; Now set up r17 as tmp
	
prestart:       
        ldi  r0.b0, max_size-1    ; Get biggest size we can read first time
        qbge precopy, r0.b0, size ; If size >= that, we're ready for first copy
        sub  r0.b0, size, 1       ; Otherwise size-1 is what we should read
	
precopy:
        lbbo &tmp.b1, from, 0, b0 ; Read bytes into regs, skipping tmp.b0
	add from, from, r0.b0     ; Advance source pointer by amount read
	add r0.b0, r0.b0, 1       ; Note we have to write one more than we read
        sbbo &tmp, to_tmp, 0, b0  ; Write to dest, including prepended byte
	sub size, size, r0.b0     ; Decrement bytes remaining by size written
        qbeq return, size, 0      ; Done if no more size
	add to_tmp, to_tmp, r0.b0 ; Advance dest by size written

        ;; FALL INTO standard memcpy loop

start:  LDI  r0.b0, max_size
        QBGE copy, r0.b0, size
        MOV  r0.b0, size
copy:
        SUB  size, size, r0.b0
        LBBO &tmp, from, 0, b0
        SBBO &tmp, to_tmp, 0, b0
        QBEQ return, size, 0
        ADD  from, from, r0.b0
        ADD  to_tmp, to_tmp, r0.b0
        JMP start
return:
        JMP r3.w2


;******************************************************************************
;* MEMCPY.ASM  - MEMCPY -  v2.2.1                                             *
;*                                                                            *
;* Copyright (c) 2013-2017 Texas Instruments Incorporated                     *
;* http://www.ti.com/                                                         *
;*                                                                            *
;*  Redistribution and  use in source  and binary forms, with  or without     *
;*  modification,  are permitted provided  that the  following conditions     *
;*  are met:                                                                  *
;*                                                                            *
;*     Redistributions  of source  code must  retain the  above copyright     *
;*     notice, this list of conditions and the following disclaimer.          *
;*                                                                            *
;*     Redistributions in binary form  must reproduce the above copyright     *
;*     notice, this  list of conditions  and the following  disclaimer in     *
;*     the  documentation  and/or   other  materials  provided  with  the     *
;*     distribution.                                                          *
;*                                                                            *
;*     Neither the  name of Texas Instruments Incorporated  nor the names     *
;*     of its  contributors may  be used to  endorse or  promote products     *
;*     derived  from   this  software  without   specific  prior  written     *
;*     permission.                                                            *
;*                                                                            *
;*  THIS SOFTWARE  IS PROVIDED BY THE COPYRIGHT  HOLDERS AND CONTRIBUTORS     *
;*  "AS IS"  AND ANY  EXPRESS OR IMPLIED  WARRANTIES, INCLUDING,  BUT NOT     *
;*  LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR     *
;*  A PARTICULAR PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL THE COPYRIGHT     *
;*  OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,     *
;*  SPECIAL,  EXEMPLARY,  OR CONSEQUENTIAL  DAMAGES  (INCLUDING, BUT  NOT     *
;*  LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,     *
;*  DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY     *
;*  THEORY OF  LIABILITY, WHETHER IN CONTRACT, STRICT  LIABILITY, OR TORT     *
;*  (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE     *
;*  OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.      *
;*                                                                            *
;******************************************************************************

