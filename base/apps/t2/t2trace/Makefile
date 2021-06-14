PROG:=t2trace
T2_12_DIR:=../../../..
COMMON_DIR:=$(T2_12_DIR)/low/lkms/include
LOCK_DIR:=$(T2_12_DIR)/low/lkms/itc
PKT_DIR:=$(T2_12_DIR)/low/pru/itcio/module/
CPPFLAGS:=-g2 -Wall -Werror
CPPFLAGS+=-I $(COMMON_DIR) -I $(LOCK_DIR) -I $(PKT_DIR) 
$(PROG):	$(PROG).cpp $(COMMON_DIR)/*.h $(LOCK_DIR)/*.h $(PKT_DIR)/*.h Makefile
	g++ $(CPPFLAGS) $< -o $@

ECHO:=/bin/echo
ARGS:=dumpevents
run:	$(PROG) 
	./$^ $(ARGS)

test5:	$(PROG) 
	$(ECHO) -n -e "\0" > /dev/itc/lockevents ; \
	$(ECHO) -n -e "\0" > /dev/itc/pktevents ; \
	sleep 5; \
	./$^ dumpevents

locks5:	$(PROG) 
	$(ECHO) -n -e "\0" > /dev/itc/lockevents ; \
	$(ECHO) -n -e "\0" > /dev/itc/pktevents ; \
	sleep 5; \
	./$^ dumplocks

packets5:	$(PROG) 
	$(ECHO) -n -e "\0" > /dev/itc/pktevents ; \
	$(ECHO) -n -e "\0" > /dev/itc/pktevents ; \
	sleep 5; \
	./$^ dumppackets

