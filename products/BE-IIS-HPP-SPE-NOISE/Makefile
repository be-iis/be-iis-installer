KDIR ?= /lib/modules/$(shell uname -r)/build
.PHONY: all module overlays clean install
all: module overlays
module:
	$(MAKE) -C $(KDIR) M=$(CURDIR)/src modules
overlays:
	$(MAKE) -C overlays/src/rpi all
install: all
	$(MAKE) -C $(KDIR) M=$(CURDIR)/src modules_install
	$(MAKE) -C overlays/src/rpi install
	depmod -a
clean:
	$(MAKE) -C $(KDIR) M=$(CURDIR)/src clean
	$(MAKE) -C overlays/src/rpi clean
