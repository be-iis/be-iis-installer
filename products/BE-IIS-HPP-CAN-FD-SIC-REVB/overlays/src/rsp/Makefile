BUILD_ROOT := ../../../build/overlay/rpi

DTS_FILES := $(wildcard *.dts)
OVERLAYS  := $(DTS_FILES:.dts=)
DTBOS     := $(addsuffix .dtbo,$(OVERLAYS))

KVER := $(shell uname -r)
KERNEL_HEADERS := /lib/modules/$(KVER)/build
COMMON_HEADERS := /usr/src/linux-headers-$(shell uname -r | sed 's/-rpi-[0-9]*/-common-rpi/')/include

DTC := dtc
CPP := cpp

CPPFLAGS := \
	-nostdinc \
	-I$(KERNEL_HEADERS)/include \
	-I$(COMMON_HEADERS) \
	-I$(KERNEL_HEADERS)/arch/arm64/boot/dts \
	-I$(KERNEL_HEADERS)/arch/arm/boot/dts \
	-undef \
	-x assembler-with-cpp

.PHONY: all clean install list

all: $(DTBOS)

%.dtbo: %.dts
	mkdir -p $(BUILD_ROOT)/$*
	$(CPP) $(CPPFLAGS) $< > $(BUILD_ROOT)/$*/$*.tmp.dts
	$(DTC) -@ -I dts -O dtb -o $(BUILD_ROOT)/$*/$@ $(BUILD_ROOT)/$*/$*.tmp.dts

install: all
	for f in $(OVERLAYS); do \
		install -m 0644 $(BUILD_ROOT)/$$f/$$f.dtbo /boot/firmware/overlays/$$f.dtbo; \
	done

clean:
	rm -rf $(BUILD_ROOT)

list:
	@printf '%s\n' $(OVERLAYS)