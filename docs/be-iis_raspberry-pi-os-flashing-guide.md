# Raspberry Pi OS Flashing + BE-IIS Installer Guide

This guide shows how to:

- download Raspberry Pi OS Lite
- flash it to an SD card
- enable SSH
- create a user before first boot
- install Git
- clone the BE-IIS installer
- run the installer

---

## Download options

### Option A: Raspberry Pi OS Lite (64-bit)

Use this for Raspberry Pi models that support the 64-bit Raspberry Pi OS release.

Official compatibility includes:

- Raspberry Pi 3B
- Raspberry Pi 3B+
- Raspberry Pi 3A+
- Raspberry Pi 4B
- Raspberry Pi 400
- Raspberry Pi 5
- Raspberry Pi 500
- Raspberry Pi 500+
- Raspberry Pi CM3
- Raspberry Pi CM3+
- Raspberry Pi CM4
- Raspberry Pi CM4S
- Raspberry Pi CM5
- Raspberry Pi Zero 2 W

Download directly:

```bash
cd ~/Downloads
wget https://downloads.raspberrypi.com/raspios_lite_arm64/images/raspios_lite_arm64-2025-12-04/2025-12-04-raspios-trixie-arm64-lite.img.xz -O raspios-lite-64bit.img.xz
```

### Option B: Raspberry Pi OS Lite (32-bit)

Use this if you want the broadest compatibility. The current 32-bit Raspberry Pi OS release is listed as compatible with **all Raspberry Pi models**.

Download directly:

```bash
cd ~/Downloads
wget https://downloads.raspberrypi.com/raspios_lite_armhf/images/raspios_lite_armhf-2025-12-04/2025-12-04-raspios-trixie-armhf-lite.img.xz -O raspios-lite-32bit.img.xz
```

### Which one should I use?

- Use **64-bit** on modern Raspberry Pi models if you want the current 64-bit system.
- Use **32-bit** if you want one image that works across all Raspberry Pi models.
- For a headless installer workflow, **Lite** is usually the right choice.

---

## Flashing the image

Replace the filename if you downloaded the 32-bit image instead of the 64-bit one.

### 1. Find the SD card

Insert the SD card:

```bash
lsblk
```

Example:

```text
sdb      32G
├─sdb1   256M
└─sdb2   ...
```

Use the correct device, for example:

```text
/dev/sdb
```

### 2. Unmount existing partitions

```bash
sudo umount /dev/sdb1 || true
sudo umount /dev/sdb2 || true
```

### 3. Flash directly from `.xz`

Example for the 64-bit image:

```bash
xzcat raspios-lite-64bit.img.xz | sudo dd of=/dev/sdb bs=4M status=progress conv=fsync
```

Example for the 32-bit image:

```bash
xzcat raspios-lite-32bit.img.xz | sudo dd of=/dev/sdb bs=4M status=progress conv=fsync
```

Wait until flashing is complete.

### 4. Re-read the partition table

```bash
sync
sudo partprobe /dev/sdb
```

If needed, unplug and reinsert the SD card.

---

## Prepare first boot

### 5. Mount the boot partition

```bash
sudo mkdir -p /mnt/rpi-boot
sudo mount /dev/sdb1 /mnt/rpi-boot
```

### 6. Enable SSH

```bash
sudo touch /mnt/rpi-boot/ssh
```

### 7. Create the user

Recent Raspberry Pi OS images require a user to be created before first boot.

```bash
echo "<username>:$(openssl passwd -6 '<password>')" | sudo tee /mnt/rpi-boot/userconf.txt
```

Replace:

- `<username>` with your username
- `<password>` with your password

### 8. Unmount the boot partition

```bash
sudo umount /mnt/rpi-boot
```

---

## First boot and login

### 9. Start the Raspberry Pi

- Insert the SD card
- Connect Ethernet
- Power on the Raspberry Pi

### 10. Connect to the Raspberry Pi

Try:

```bash
ping raspberrypi.local
```

or directly:

```bash
ssh <username>@raspberrypi.local
```

### 11. First login

```bash
ssh <username>@raspberrypi.local
```

---

## Initial setup on the Raspberry Pi

### 12. Update the system

```bash
sudo apt update
sudo apt upgrade -y
```

### 13. Install Git

```bash
sudo apt install -y git
```

---

## Install BE-IIS

### 14. Clone the repository

```bash
git clone https://github.com/<your-org>/be-iis-installer.git
```

### 15. Run the installer

```bash
cd be-iis-installer
./scripts/install/install-all.sh
```

---

## Done

The Raspberry Pi is now prepared and the BE-IIS installer has been executed.
