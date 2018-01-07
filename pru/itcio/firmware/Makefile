# 
# Copyright (c) 2016 Zubeen Tolani <ZeekHuge - zeekhuge@gmail.com>
# Makefile to make PRU_inlineASM_blinky project
#
# The make file is tried to be made as generic as possible
# So that it can be used to compile other programs too
# 
# Usage:
#	name your main source file as main_pru1.c or main_pru0.c
# 	add targets to variable TARGETS
#	add other files required while linking in variable LINK_PRU1(0)_FW
#	add compile targets, as added to LINK_PRU1(0)_FW for other files.
# 

# PRU_CGT environment variable must point to the TI PRU compiler directory. E.g.:
PRU_CGT:=/usr/share/ti/cgt-pru

LINKER_COMMAND_FILE=./AM335x_PRU.cmd
LIBS=--library=../../lib/rpmsg_lib.lib
INCLUDE+=--include_path=../../include
INCLUDE+=--include_path=../../include/am335x
INCLUDE+=--include_path=../common
INCLUDE+=--include_path=/usr/include/asm-generic
# stack and heap sizes set in AM335x_PRU.cmd
# STACK_SIZE=0x300
# HEAP_SIZE=0x100


#CFLAGS=--preproc_only -v3 -O2 --display_error_number --endian=little --hardware_mac=on --obj_directory=$(GEN_DIR) --pp_directory=$(GEN_DIR)
CFLAGS=-v3 -O4 --symdebug:none --gen_opt_info=2 --display_error_number --endian=little --hardware_mac=on --obj_directory=$(GEN_DIR) --pp_directory=$(GEN_DIR) -ppd -ppa -al
#LFLAGS=--reread_libs --warn_sections --stack_size=$(STACK_SIZE) --heap_size=$(HEAP_SIZE)
LFLAGS=-o4 --reread_libs --warn_sections


GEN_DIR=gen

PRU1_FW		=$(GEN_DIR)/main_pru1_fw.out
PRU0_FW		=$(GEN_DIR)/main_pru0_fw.out


# -----------------------------------------------------
# Variable to edit in the makefile

# add the required firmwares to TARGETS
 TARGETS		=$(PRU1_FW) $(PRU0_FW)
#TARGETS		=$(PRU1_FW)

#------------------------------------------------------
# 'Standard organization' C source files
CSRC_FILES+=Buffers.c
CSRC_FILES+=LinuxIO.c
CSRC_FILES+=SpecialPackets.c
CSRC_FILES+=main.c
CHDR_FILES:=$(patsubst %.c,%.h,$(CSRC_FILES))
COBJ0_FILES:=$(patsubst %.c,$(GEN_DIR)/%_pru0.object,$(CSRC_FILES))
COBJ1_FILES:=$(patsubst %.c,$(GEN_DIR)/%_pru1.object,$(CSRC_FILES))

# Shared state source files
SHARED_STATE_DIR:=../common
SHARED_STATE_C_FILENAMES:=PacketBuffer.c SharedState.c
SHARED_STATE_C_FILES:=$(patsubst %.c,$(SHARED_STATE_DIR)/%.c,$(SHARED_STATE_C_FILENAMES))
SHARED_STATE_HDR_FILES:=$(patsubst %.c,%.h,$(SHARED_STATE_C_FILES))
SHARED_STATE_COBJ_FILES+=$(patsubst $(SHARED_STATE_DIR)/%.c,$(GEN_DIR)/%_pru.object,$(SHARED_STATE_C_FILES))
COBJ0_FILES+=$(SHARED_STATE_COBJ_FILES)
COBJ1_FILES+=$(SHARED_STATE_COBJ_FILES)

# 'Standard organization' asm source files
ASRC_FILES+=PacketRunner.asm
ASRC_FILES+=Threads.asm
AOBJ0_FILES:=$(patsubst %.asm,$(GEN_DIR)/%_pru0.object,$(ASRC_FILES))
AOBJ1_FILES:=$(patsubst %.asm,$(GEN_DIR)/%_pru1.object,$(ASRC_FILES))

OBJ0_FILES:=$(COBJ0_FILES) $(AOBJ0_FILES)
OBJ1_FILES:=$(COBJ1_FILES) $(AOBJ1_FILES)

ALL_DEP:=Makefile
C_ALL_DEP:=$(ALL_DEP) $(CHDR_FILES) prux.h
ASM_ALL_DEP:=$(C_ALL_DEP) structs.asm macros.asm

.PHONY: build abslist
build:	$(TARGETS)
	@echo '-	Generated firmwares are : $^'

# LD
$(PRU1_FW):	$(OBJ1_FILES) $(LINKER_COMMAND_FILE) 
	@echo 'LD	$@'
	@$(PRU_CGT)/bin/lnkpru -i$(PRU_CGT)/lib -i$(PRU_CGT)/include $(LFLAGS) --map_file=$@.map -o $@ $^  --library=libc.a $(LIBS) &&\
	head -15 $@.map | tail -1 | cut -b 1-14,54-63 | tr '\n' ' ' &&\
	head -19 $@.map | tail -2 | cut -b 1-14,54-63 | tr '\n' ' ' &&\
	echo

$(PRU0_FW):	$(OBJ0_FILES) $(LINKER_COMMAND_FILE) 
	@echo 'LD	$@' 
	@$(PRU_CGT)/bin/lnkpru -i$(PRU_CGT)/lib -i$(PRU_CGT)/include $(LFLAGS) --map_file=$@.map -o $@ $^  --library=libc.a $(LIBS) &&\
	head -15 $@.map | tail -1 | cut -b 1-14,54-63 | tr '\n' ' ' &&\
	head -19 $@.map | tail -2 | cut -b 1-14,54-63 | tr '\n' ' ' &&\
	echo

# CC
$(GEN_DIR)/%_pru.object: $(SHARED_STATE_DIR)/%.c $(SHARED_STATE_DIR)/%.h $(C_ALL_DEP)
	@mkdir -p $(GEN_DIR)
	@echo 'CC	$< (pru[01])'
	@$(PRU_CGT)/bin/clpru --include_path=$(PRU_CGT)/include $(INCLUDE) $(CFLAGS) -fe $@ $<

$(GEN_DIR)/%_pru0.object: %.c %.h $(C_ALL_DEP)
	@mkdir -p $(GEN_DIR)
	@echo 'CC	$< (pru0)'
	@$(PRU_CGT)/bin/clpru -DON_PRU=0 --include_path=$(PRU_CGT)/include $(INCLUDE) $(CFLAGS) -fe $@ $<

$(GEN_DIR)/%_pru1.object: %.c %.h $(C_ALL_DEP)
	@mkdir -p $(GEN_DIR)
	@echo 'CC	$< (pru1)'
	@$(PRU_CGT)/bin/clpru -DON_PRU=1 --include_path=$(PRU_CGT)/include $(INCLUDE) $(CFLAGS) -fe $@ $<


# ASM
$(GEN_DIR)/%_pru0.object: %.asm $(ASM_ALL_DEP)
	@mkdir -p $(GEN_DIR)
	@echo 'ASM	$< (pru0)'
	@$(PRU_CGT)/bin/clpru -DON_PRU=0 --include_path=$(PRU_CGT)/include $(INCLUDE) $(CFLAGS) -fe $@ $<

$(GEN_DIR)/%_pru1.object: %.asm $(ASM_ALL_DEP)
	@mkdir -p $(GEN_DIR)
	@echo 'ASM	$< (pru1)'
	@$(PRU_CGT)/bin/clpru -DON_PRU=1 --include_path=$(PRU_CGT)/include $(INCLUDE) $(CFLAGS) -fe $@ $<


.PHONY: install copy_pru0_fw copy_pru1_fw reboot_pru_1 reboot_pru_0

# COMMON


#Let module side do the rebooting
#WAS:install: build copyfw rebootprus
install: build copyfw

copyfw:	copy_pru0_fw copy_pru1_fw

rebootprus:	 reboot_pru0 reboot_pru1

copy_pru1_fw:
	@echo '-	copying firmware to /lib/firmware/am335x_pru1_fw'
	@cp $(PRU1_FW) /lib/firmware/am335x-pru1-fw

copy_pru0_fw: $(PRU0_FW)
	@echo '-	copying firmware to /lib/firmware/am335x_pru0_fw'
	@cp $(PRU0_FW) /lib/firmware/am335x-pru0-fw

reboot_pru1:
	@echo '-	ensuring itc_pkt module is removed'
	$(shell modprobe -r itc_pkt || exit 0)
	@echo '-	rebooting pru core 1'
	$(shell echo "4a338000.pru1" > /sys/bus/platform/drivers/pru-rproc/unbind 2> /dev/null)
	$(shell echo "4a338000.pru1" > /sys/bus/platform/drivers/pru-rproc/bind)
	@echo "-	pru core 1 is now loaded with $(PRU1_FW)"

reboot_pru0:
	@echo '-	ensuring itc_pkt module is removed'
	$(shell modprobe -r itc_pkt || exit 0)
	@echo '-	rebooting pru core 0'
	$(shell echo "4a334000.pru0" > /sys/bus/platform/drivers/pru-rproc/unbind 2> /dev/null)
	$(shell echo "4a334000.pru0" > /sys/bus/platform/drivers/pru-rproc/bind)
	@echo "-	pru core 0 is now loaded with $(PRU0_FW)"


.PHONY: clean
clean:
	@echo 'CLEAN	.'
	@rm -f *.abs *.lst *~
	@rm -rf $(GEN_DIR)
