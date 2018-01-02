BUF_DIR:=../../pru/itcio/common
CFLAGS+=-I $(BUF_DIR) -g2
LDFLAGS+=

all:	buffy

%.o:	%.c Makefile
	$(CC) $(CFLAGS) -c -Wall -Werror $< 

PacketBuffer.o:	$(BUF_DIR)/PacketBuffer.c $(BUF_DIR)/PacketBuffer.h Makefile
	$(CC) $(CFLAGS) -c -Wall -Werror $< 

SharedState.o:	$(BUF_DIR)/SharedState.c $(BUF_DIR)/SharedState.h Makefile
	$(CC) $(CFLAGS) -c -Wall -Werror $< 

buffy:	buffy.o PacketBuffer.o SharedState.o
	$(CC) $(LDFLAGS) $^ -o $@

clean:	FORCE
	rm -f *~ *o

.PHONY:	FORCE
