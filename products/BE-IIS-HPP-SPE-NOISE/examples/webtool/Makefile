PYTHON ?= python3
INSTALL_DIR ?= /opt/be-iis/BE-IIS-HPP-SPE-NOISE/examples/webtool
SERVICE ?= beiis-noise-webtool.service

.PHONY: run install enable disable status

run:
	$(PYTHON) noise_webtool.py

install:
	sudo install -d -m 0755 $(INSTALL_DIR)
	sudo install -m 0755 noise_webtool.py $(INSTALL_DIR)/noise_webtool.py
	sudo install -m 0644 $(SERVICE) /etc/systemd/system/$(SERVICE)
	sudo systemctl daemon-reload

enable: install
	sudo systemctl enable --now $(SERVICE)

disable:
	sudo systemctl disable --now $(SERVICE)

status:
	systemctl status $(SERVICE)
