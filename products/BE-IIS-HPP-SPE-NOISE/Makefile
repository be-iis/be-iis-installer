obj-m += beiis_hpp_noise.o
KDIR ?= /lib/modules/$(shell uname -r)/build
DTC ?= dtc
OVERLAY := overlays/beiis-hpp-spe-noise.dtbo
.PHONY: all module overlay clean install
all: module overlay
module:
	$(MAKE) -C $(KDIR) M=$(CURDIR)/src modules
overlay: $(OVERLAY)
$(OVERLAY): overlays/beiis-hpp-spe-noise-overlay.dts
	$(DTC) -@ -I dts -O dtb -o $@ $<
install: all
	$(MAKE) -C $(KDIR) M=$(CURDIR)/src modules_install
	install -D -m 0644 $(OVERLAY) /boot/firmware/overlays/beiis-hpp-spe-noise.dtbo
	depmod -a
clean:
	$(MAKE) -C $(KDIR) M=$(CURDIR)/src clean
	rm -f $(OVERLAY)
