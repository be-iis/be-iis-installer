DTC ?= dtc
CPP ?= gcc
KERNEL_HEADERS ?= /lib/modules/$(shell uname -r)/build
BUILD_DIR ?= ../../build/rpi

# Raspberry Pi headers often split shared dt-bindings into a common package.
KERNEL_COMMON_HEADERS ?= /usr/src/linux-headers-$(shell uname -r | sed 's/-rpi-.*//')-common-rpi
CPP_INCLUDES := -I$(KERNEL_HEADERS)/include -I$(KERNEL_COMMON_HEADERS)/include -I.

DTC_FLAGS := -@ -H epapr -Wno-unit_address_vs_reg
# Build the canonical REVA overlays, not the duplicate short-name sources.
DTS_FILES := $(sort $(wildcard BE-IIS-HPP-T1S-ADI-REVA-*.dts))
DTBO_FILES := $(patsubst %.dts,$(BUILD_DIR)/%.dtbo,$(DTS_FILES))

all: $(DTBO_FILES)

$(BUILD_DIR):
	mkdir -p $@

%.pp.dts: %.dts
	@test -f "$(KERNEL_COMMON_HEADERS)/include/dt-bindings/interrupt-controller/irq.h" || \
		test -f "$(KERNEL_HEADERS)/include/dt-bindings/interrupt-controller/irq.h" || \
		{ echo "ERROR: dt-bindings missing; install matching kernel header packages" >&2; exit 1; }
	$(CPP) -E -P -x assembler-with-cpp $(CPP_INCLUDES) -o $@ $<

$(BUILD_DIR)/%.dtbo: %.pp.dts | $(BUILD_DIR)
	$(DTC) $(DTC_FLAGS) -I dts -O dtb -o $@ $<

clean:
	rm -f *.pp.dts
	rm -rf $(BUILD_DIR)

.PHONY: all clean
