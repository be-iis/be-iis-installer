CC ?= gcc
CFLAGS ?= -O2 -Wall -Wextra -Werror
TARGET := beiis-machxo2-flash

all: $(TARGET)

$(TARGET): $(TARGET).c
	$(CC) $(CFLAGS) -o $@ $<

clean:
	rm -f $(TARGET)

.PHONY: all clean
