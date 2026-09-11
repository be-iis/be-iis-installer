BUILD_ROOT := ../../build/rpi
DTS_FILES := $(wildcard *.dts)
OVERLAYS := $(DTS_FILES:.dts=)
DTBOS := $(addprefix $(BUILD_ROOT)/,$(addsuffix .dtbo,$(OVERLAYS)))
DTC ?= dtc
.PHONY: all clean install
all: $(DTBOS)
$(BUILD_ROOT)/%.dtbo: %.dts
	mkdir -p $(BUILD_ROOT)
	$(DTC) -@ -I dts -O dtb -o $@ $<
install: all
	for f in $(OVERLAYS); do install -D -m 0644 $(BUILD_ROOT)/$$f.dtbo /boot/firmware/overlays/$$f.dtbo; done
clean:
	rm -rf $(BUILD_ROOT)
