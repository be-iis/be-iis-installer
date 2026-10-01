DTC ?= dtc
CPP ?= gcc
KERNEL_HEADERS ?= /lib/modules/$(shell uname -r)/build
BUILD_DIR ?= ../../build/rpi

CPP_INCLUDES := -I$(KERNEL_HEADERS)/include -I.
DTC_FLAGS := -@ -H epapr -Wno-unit_address_vs_reg
DTS_FILES := $(wildcard *.dts)
DTBO_FILES := $(patsubst %.dts,$(BUILD_DIR)/%.dtbo,$(DTS_FILES))

all: $(DTBO_FILES)

$(BUILD_DIR):
	mkdir -p $@

%.pp.dts: %.dts
	$(CPP) -E -P -x assembler-with-cpp $(CPP_INCLUDES) -o $@ $<

$(BUILD_DIR)/%.dtbo: %.pp.dts | $(BUILD_DIR)
	$(DTC) $(DTC_FLAGS) -I dts -O dtb -o $@ $<

clean:
	rm -f *.pp.dts
	rm -rf $(BUILD_DIR)

.PHONY: all clean
