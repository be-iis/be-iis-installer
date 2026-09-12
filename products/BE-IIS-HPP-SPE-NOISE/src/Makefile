# SPDX-License-Identifier: GPL-2.0-or-later
#
# BE-IIS HPP SPE Noise Generator kernel module
#
# Examples:
#   make
#   sudo make install
#   sudo make uninstall
#

obj-m += beiis_hpp_noise.o

KERNELRELEASE ?= $(shell uname -r)
KDIR          ?= /lib/modules/$(KERNELRELEASE)/build
MODULE        := beiis_hpp_noise.ko
MODDIR        ?= /lib/modules/$(KERNELRELEASE)/updates
PWD           := $(shell pwd)

.PHONY: all clean install uninstall help

all:
	$(MAKE) -C $(KDIR) M=$(PWD) modules

clean:
	$(MAKE) -C $(KDIR) M=$(PWD) clean

install: all
	install -D -m 0644 $(MODULE) $(MODDIR)/$(MODULE)
	depmod -a $(KERNELRELEASE)

uninstall:
	rm -f $(MODDIR)/$(MODULE)
	depmod -a $(KERNELRELEASE)

help:
	@echo "Targets:"
	@echo "  make                 Build $(MODULE) for the running kernel"
	@echo "  make clean           Remove generated build files"
	@echo "  sudo make install    Install the module to $(MODDIR)"
	@echo "  sudo make uninstall  Remove the installed module"
	@echo
	@echo "Override KERNELRELEASE, KDIR or MODDIR if required."
