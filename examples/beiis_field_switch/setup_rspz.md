# 📦 Setup: RSP-B (Raspberry Pi Zero 2 W)

## ⚙️ Prepare Raspberry Pi OS (64-bit)

```bash
cd ~/Downloads

lsblk

xzcat raspios-lite-64bit.img.xz | sudo dd of=/dev/sdb bs=4M status=progress conv=fsync

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

## 🔌 Initial Access

Initial login via USB-to-LAN adapter

---

## 🔧 System Configuration

```bash
ssh <username>@raspberrypi.local

sudo hostnamectl set-hostname rspz
sudo reboot

ssh <username>@rspz.local
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

Instance Mode I   → 10BASE-T1S  
Instance Mode II  → 10BASE-T1L  
Instance Mode III → LAN (SPI Ethernet)  

```bash
reboot
```

---

## 🔎 Result

```bash
ifconfig
```

Expected:

- beiis-t1s0 → 10BASE-T1S  
- beiis-t1l1 → 10BASE-T1L  
- beiis-lan2 → SPI Ethernet  
- eth0 → USB-to-LAN / Management  
