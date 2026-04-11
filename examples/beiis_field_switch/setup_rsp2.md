# 📦 Setup: RSP-A (Raspberry Pi 2B)

## 🔧 Configuration

- 1× Standard Ethernet (LAN)
- 1× 10BASE-T1S  
- 1× 10BASE-T1L (powered via PoSPE)

---

## ⚙️ Prepare Raspberry Pi OS

Follow:
https://github.com/be-iis/be-iis-installer/blob/main/docs/be-iis_raspberry-pi-os-flashing-guide.md

```bash
cd ~/Downloads

wget https://downloads.raspberrypi.com/raspios_lite_armhf/images/raspios_lite_armhf-2025-12-04/2025-12-04-raspios-trixie-armhf-lite.img.xz -O raspios-lite-32bit.img.xz

lsblk

xzcat raspios-lite-32bit.img.xz | sudo dd of=/dev/sdb bs=4M status=progress conv=fsync

sync
sudo partprobe /dev/sdb

sudo mkdir -p /mnt/rpi-boot
sudo mount /dev/sdb1 /mnt/rpi-boot

sudo touch /mnt/rpi-boot/ssh

echo "<username>:$(openssl passwd -6 '<password>')" | sudo tee /mnt/rpi-boot/userconf.txt

sudo umount /mnt/rpi-boot
sync
```

---

## 🔧 System Configuration (optional)

```bash
ssh <username>@raspberrypi.local

sudo hostnamectl set-hostname rsp2
sudo reboot

ssh <username>@rsp2.local
```

---

## 🚀 BE-IIS Installation

```bash
sudo apt install -y git

git clone https://github.com/be-iis/be-iis-installer.git
cd be-iis-installer

./scripts/install/install-all.sh
```

---

## 🔀 Instance Mode Configuration

10BASE-T1S → Instance Mode I  
10BASE-T1L → Instance Mode II  

```bash
reboot
```

---

## 🔎 Result

```bash
ifconfig
```

Expected:

- eth0 → Standard Ethernet  
- beiis-t1s0 → 10BASE-T1S  
- beiis-t1l1 → 10BASE-T1L  
