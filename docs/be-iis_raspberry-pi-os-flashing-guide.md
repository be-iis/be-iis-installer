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

Both Lite and Full versions are supported.

Official compatibility includes:

- Raspberry Pi 3B
- Raspberry Pi 3B+
- Raspberry Pi 3A+
- Raspberry Pi 4B
- Raspberry Pi 5
- Raspberry Pi Zero 2 W

Download directly:
Lite (minimal system, no desktop)
```bash
cd ~/Downloads
wget https://downloads.raspberrypi.com/raspios_lite_arm64/images/raspios_lite_arm64-2025-12-04/2025-12-04-raspios-trixie-arm64-lite.img.xz -O raspios-lite-64bit.img.xz
```
Full (with desktop environment)
```bash
cd ~/Downloads
wget https://downloads.raspberrypi.com/raspios_full_arm64/images/raspios_full_arm64-2025-12-04/2025-12-04-raspios-trixie-arm64-full.img.xz -O raspios-full-64bit.img.xz
```

### Option B: Raspberry Pi OS Lite (32-bit)

Use this if you want the broadest compatibility. The current 32-bit Raspberry Pi OS release is listed as compatible with **all Raspberry Pi models**.

Download directly:

```bash
cd ~/Downloads
wget https://downloads.raspberrypi.com/raspios_lite_armhf/images/raspios_lite_armhf-2025-12-04/2025-12-04-raspios-trixie-armhf-lite.img.xz -O raspios-lite-32bit.img.xz
```
Full (with desktop environment)
```bash
cd ~/Downloads
wget https://downloads.raspberrypi.com/raspios_full_armhf/images/raspios_full_armhf-2025-12-04/2025-12-04-raspios-trixie-armhf-full.img.xz -O raspios-full-32bit.img.xz
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
â”œâ”€sdb1   256M
â””â”€sdb2   ...
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

Raspberry Pi OS Trixie images released since late November 2025 use
`cloud-init`. Configure the first user, hostname, SSH password login, and SSH
key in the `user-data` file. The older `userconf.txt` and `hostname` files are
not used by this guide.

### 5. Mount the boot partition

```bash
sudo mkdir -p /mnt/rpi-boot
sudo mount /dev/sdb1 /mnt/rpi-boot
```

### 6. Configure hostname, user, password, and SSH

The following block starts in the mounted boot directory. Change
`PI_HOSTNAME` and `PI_USERNAME` before running it.

The SSH key is generated only if it does not already exist. The same key file
can therefore be reused for every Raspberry Pi prepared on this computer.

Copy and paste the complete block:

```bash
cd /mnt/rpi-boot

PI_HOSTNAME="pi2"
PI_USERNAME="philipp"
SSH_KEY_FILE="$HOME/.ssh/id_ed25519_be_iis_pis"

mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"

if [[ ! -f "$SSH_KEY_FILE" ]]; then
    ssh-keygen -t ed25519 \
        -f "$SSH_KEY_FILE" \
        -N "" \
        -C "be-iis-pis"
fi

chmod 600 "$SSH_KEY_FILE"
chmod 644 "${SSH_KEY_FILE}.pub"

while true; do
    read -rsp "Password for ${PI_USERNAME}: " PI_PASSWORD
    echo
    read -rsp "Repeat password: " PI_PASSWORD_REPEAT
    echo
    [[ "$PI_PASSWORD" == "$PI_PASSWORD_REPEAT" ]] && break
    unset PI_PASSWORD PI_PASSWORD_REPEAT
    echo "Passwords do not match. Please try again." >&2
done

PASSWORD_HASH="$(printf '%s' "$PI_PASSWORD" | openssl passwd -6 -stdin)"
SSH_PUBLIC_KEY="$(cat "${SSH_KEY_FILE}.pub")"
unset PI_PASSWORD PI_PASSWORD_REPEAT

sudo tee user-data >/dev/null <<EOF
#cloud-config
hostname: ${PI_HOSTNAME}
manage_etc_hosts: true

users:
  - name: ${PI_USERNAME}
    shell: /bin/bash
    groups:
      - adm
      - sudo
    lock_passwd: false
    hashed_passwd: '${PASSWORD_HASH}'
    sudo:
      - ALL=(ALL) NOPASSWD:ALL
    ssh_authorized_keys:
      - ${SSH_PUBLIC_KEY}

ssh_pwauth: true
enable_ssh: true
disable_root: true

chpasswd:
  expire: false
EOF

sudo touch ssh
sudo rm -f userconf userconf.txt hostname
sync

unset PASSWORD_HASH SSH_PUBLIC_KEY
echo "Prepared ${PI_USERNAME}@${PI_HOSTNAME}.local"
```

The private key remains on the setup computer:

```text
~/.ssh/id_ed25519_be_iis_pis
```

Keep this private key secure and back it up. Anyone who obtains it can access
all Raspberry Pis configured with its public key.

### 7. Unmount the boot partition

```bash
cd ~
sudo umount /mnt/rpi-boot
sync
```

---

## First boot and login

### 8. Start the Raspberry Pi

- Insert the SD card
- Connect Ethernet
- Power on the Raspberry Pi

### 9. Connect to the Raspberry Pi

Replace the hostname and username if you selected different values:

```bash
ping pi2.local
```

Connect using the shared BE-IIS Pi key:

```bash
ssh -i ~/.ssh/id_ed25519_be_iis_pis philipp@pi2.local
```

Password login is also enabled as a fallback:

```bash
ssh -o PubkeyAuthentication=no \
    -o PreferredAuthentications=password \
    philipp@pi2.local
```

If `.local` name resolution is not available, use the Pi's IP address instead.

---

## Initial setup on the Raspberry Pi

### 10. (Optional) Update the system âš ï¸

```bash
sudo apt update
sudo apt upgrade -y
```

âš ï¸ Important: Reboot required after upgrade
If a kernel update was installed, you must reboot before continuing:
```bash
sudo reboot
```
ðŸ“Œ Note
Skipping the reboot may lead to:

Kernel module build failures
Missing or mismatched headers
Installer errors in BE-IIS scripts

### 11. Install Git

```bash
sudo apt install -y git
```

---

## Install BE-IIS

### 12. Clone the repository

```bash
git clone https://github.com/be-iis/be-iis-installer.git
```

### 13. Run the installer

```bash
cd be-iis-installer
./scripts/install/install-all.sh
```

---

## Done

The Raspberry Pi is now prepared and the BE-IIS installer has been executed.

