# =============================================================================
# Paths
# =============================================================================

MAKEFILE_DIR := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
BUILD_ROOT   := $(abspath $(MAKEFILE_DIR)/../../ethtool)
SRC_CACHE    := $(BUILD_ROOT)/src
PREFIX_LOCAL := $(BUILD_ROOT)/prefix

# =============================================================================
# Toolchain / environment
# =============================================================================

CC           ?= gcc
CXX          ?= g++
AR           ?= ar
RANLIB       ?= ranlib
STRIP        ?= strip
PKG_CONFIG   ?= pkg-config

PREFIX_SYS   ?= /usr
SBIN_DIR_SYS ?= /usr/sbin
LIBDIR_SYS   ?= /usr/lib/aarch64-linux-gnu
DESTDIR      ?=

COMMON_CFLAGS  ?= -O2 -fPIC
COMMON_LDFLAGS ?=

JOBS         := $(shell nproc 2>/dev/null || echo 4)

PKG_CONFIG_PATH_LOCAL := $(PREFIX_LOCAL)/lib/pkgconfig
LOCAL_CFLAGS 	:= $(COMMON_CFLAGS) -D_DEFAULT_SOURCE -I$(PREFIX_LOCAL)/include
LOCAL_LDFLAGS         := $(COMMON_LDFLAGS) -L$(PREFIX_LOCAL)/lib
LOCAL_RUNPATH         := -Wl,-rpath,$(PREFIX_LOCAL)/lib

# =============================================================================
# Sources / versions
# =============================================================================

LIBMNL_VER    := 1.0.3
LIBMNL_TARBZ  := libmnl-$(LIBMNL_VER).tar.bz2
LIBMNL_URL    := https://www.netfilter.org/projects/libmnl/files/$(LIBMNL_TARBZ)
LIBMNL_DIR    := $(BUILD_ROOT)/libmnl-$(LIBMNL_VER)

ETHTOOL_GIT   := https://git.kernel.org/pub/scm/network/ethtool/ethtool.git
ETHTOOL_DIR   := $(BUILD_ROOT)/ethtool

# =============================================================================
# Phony targets
# =============================================================================

.PHONY: all env fetch libmnl ethtool install install-libmnl install-ethtool
.PHONY: clean distclean builddirs show-run-env

all: env fetch libmnl ethtool

env:
	@echo "==> Native build on target"
	@echo "==> CC:               $(CC)"
	@echo "==> BUILD_ROOT:       $(BUILD_ROOT)"
	@echo "==> PREFIX_LOCAL:     $(PREFIX_LOCAL)"
	@echo "==> PREFIX_SYS:       $(PREFIX_SYS)"
	@echo "==> SBIN_DIR_SYS:     $(SBIN_DIR_SYS)"
	@echo "==> LIBDIR_SYS:       $(LIBDIR_SYS)"
	@echo "==> DESTDIR:          $(DESTDIR)"
	@echo "==> PKG_CONFIG_PATH:  $(PKG_CONFIG_PATH_LOCAL)"
	@echo "==> Required packages:"
	@echo "    autoconf automake libtool pkg-config bison flex make gcc g++ git wget"
	@echo "==> 'make' only builds locally"
	@echo "==> 'sudo make install' installs ethtool into the system"
	@echo

fetch: $(LIBMNL_DIR)/.unpacked $(ETHTOOL_DIR)/.cloned
	@echo "==> Sources fetched"

libmnl: $(LIBMNL_DIR)/.installed-local

ethtool: $(ETHTOOL_DIR)/.built

install: install-ethtool
	@echo "==> Installed successfully"

install-libmnl: $(LIBMNL_DIR)/.installed-local
	@echo "==> libmnl already installed locally into $(PREFIX_LOCAL)"

install-ethtool: $(ETHTOOL_DIR)/.installed-system

show-run-env:
	@echo
	@echo "To run the locally built ethtool before system install:"
	@echo "  export LD_LIBRARY_PATH=$(PREFIX_LOCAL)/lib:\$$LD_LIBRARY_PATH"
	@echo "  $(ETHTOOL_DIR)/ethtool --version"
	@echo

# =============================================================================
# Helpers
# =============================================================================

builddirs:
	@mkdir -p "$(BUILD_ROOT)" "$(SRC_CACHE)" "$(PREFIX_LOCAL)"

# =============================================================================
# libmnl (local build + local install only)
# =============================================================================

$(LIBMNL_DIR)/.unpacked: | builddirs
	@echo "==> Fetch libmnl"
	@if [ ! -f "$(SRC_CACHE)/$(LIBMNL_TARBZ)" ]; then \
		wget -O "$(SRC_CACHE)/$(LIBMNL_TARBZ)" "$(LIBMNL_URL)"; \
	else \
		echo "==> libmnl tarball already present"; \
	fi
	@if [ ! -d "$(LIBMNL_DIR)" ]; then \
		tar -xjf "$(SRC_CACHE)/$(LIBMNL_TARBZ)" -C "$(BUILD_ROOT)"; \
	else \
		echo "==> libmnl source already unpacked"; \
	fi
	@touch "$@"

$(LIBMNL_DIR)/.configured: $(LIBMNL_DIR)/.unpacked
	@echo "==> Configure libmnl (local prefix)"
	cd "$(LIBMNL_DIR)" && \
	CFLAGS="$(COMMON_CFLAGS)" \
	LDFLAGS="$(COMMON_LDFLAGS)" \
	./configure \
		--prefix="$(PREFIX_LOCAL)" \
		--libdir="$(PREFIX_LOCAL)/lib"
	@touch "$@"

$(LIBMNL_DIR)/.built: $(LIBMNL_DIR)/.configured
	@echo "==> Build libmnl"
	$(MAKE) -C "$(LIBMNL_DIR)" -j"$(JOBS)"
	@touch "$@"

$(LIBMNL_DIR)/.installed-local: $(LIBMNL_DIR)/.built
	@echo "==> Install libmnl into local prefix"
	$(MAKE) -C "$(LIBMNL_DIR)" install
	-@find "$(PREFIX_LOCAL)/lib" -type f -name "*.so*" -exec $(STRIP) --strip-unneeded {} \; 2>/dev/null || true
	@touch "$@"

# =============================================================================
# ethtool (build against local libmnl)
# =============================================================================

$(ETHTOOL_DIR)/.cloned: | builddirs
	@echo "==> Fetch ethtool"
	@if [ ! -d "$(ETHTOOL_DIR)/.git" ]; then \
		git clone --depth 1 "$(ETHTOOL_GIT)" "$(ETHTOOL_DIR)"; \
	else \
		echo "==> ethtool repo exists, refreshing"; \
		cd "$(ETHTOOL_DIR)" && git fetch --depth 1 origin && git reset --hard origin/HEAD; \
	fi
	@touch "$@"

$(ETHTOOL_DIR)/.autogen: $(ETHTOOL_DIR)/.cloned
	@echo "==> Run autogen for ethtool"
	cd "$(ETHTOOL_DIR)" && NOCONFIGURE=1 ./autogen.sh
	@touch "$@"

$(ETHTOOL_DIR)/.configured: $(ETHTOOL_DIR)/.autogen $(LIBMNL_DIR)/.installed-local
	@echo "==> Configure ethtool (using local libmnl)"
	cd "$(ETHTOOL_DIR)" && \
	PKG_CONFIG_PATH="$(PKG_CONFIG_PATH_LOCAL)" \
	PKG_CONFIG="$(PKG_CONFIG)" \
	CFLAGS="$(LOCAL_CFLAGS)" \
	LDFLAGS="$(LOCAL_LDFLAGS) $(LOCAL_RUNPATH)" \
	./configure \
		--prefix="$(PREFIX_SYS)" \
		--sbindir="$(SBIN_DIR_SYS)"
	@touch "$@"

$(ETHTOOL_DIR)/.built: $(ETHTOOL_DIR)/.configured
	@echo "==> Build ethtool"
	$(MAKE) -C "$(ETHTOOL_DIR)" -j"$(JOBS)"
	@touch "$@"

$(ETHTOOL_DIR)/.installed-system: $(ETHTOOL_DIR)/.built
	@echo "==> Install ethtool into system"
	$(MAKE) -C "$(ETHTOOL_DIR)" DESTDIR="$(DESTDIR)" install
	@touch "$@"

# =============================================================================
# Cleanup
# =============================================================================

clean:
	@echo "==> Clean"
	-@$(MAKE) -C "$(LIBMNL_DIR)" clean 2>/dev/null || true
	-@$(MAKE) -C "$(ETHTOOL_DIR)" clean 2>/dev/null || true
	-@rm -f "$(LIBMNL_DIR)/.configured" "$(LIBMNL_DIR)/.built" "$(LIBMNL_DIR)/.installed-local"
	-@rm -f "$(ETHTOOL_DIR)/.autogen" "$(ETHTOOL_DIR)/.configured" "$(ETHTOOL_DIR)/.built" "$(ETHTOOL_DIR)/.installed-system"

distclean:
	@echo "==> Distclean"
	-@rm -rf "$(BUILD_ROOT)"
