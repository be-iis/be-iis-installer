# 📦 Kernel Module Build Scripts (Quick Usage)

This section describes how to download and execute the kernel module build scripts directly on a Raspberry Pi using `wget`.

---

## 🔧 Prerequisites

Run once:

```bash
sudo apt update
sudo apt install -y wget build-essential
```

(Optional – if not already done)

```bash
./scripts/bootstrap/prepare-rpi-build-env.sh
```

---

## 🚀 Download + Execute Scripts

### 📡 LAN865x

```bash
wget -O lan865x_mod_build.sh \
https://raw.githubusercontent.com/be-iis/be-iis-installer/main/tools/kernel/lan685x_mod_build.sh

chmod +x lan865x_mod_build.sh
./lan865x_mod_build.sh
```

---

### 🌐 KSZ8851

```bash
wget -O ksz8851_mod_build.sh \
https://raw.githubusercontent.com/be-iis/be-iis-installer/main/tools/kernel/kz8851_mod_build.sh

chmod +x ksz8851_mod_build.sh
./ksz8851_mod_build.sh
```

---

### 🧪 ADIN1110

```bash
wget -O adin1110_mod_build.sh \
https://raw.githubusercontent.com/be-iis/be-iis-installer/main/tools/kernel/adin1110_mod_build.sh

chmod +x adin1110_mod_build.sh
./adin1110_mod_build.sh
```

---

### 🚗 MCP251xfd (CAN FD)

```bash
wget -O mcp251xfd_mod_build.sh \
https://raw.githubusercontent.com/be-iis/be-iis-installer/main/tools/kernel/mcp251xfd_mod_build.sh

chmod +x mcp251xfd_mod_build.sh
./mcp251xfd_mod_build.sh
```

---

### 🔌 SC16IS7xx (UART Bridge)

```bash
wget -O sc16is7xx_mod_build.sh \
https://raw.githubusercontent.com/be-iis/be-iis-installer/main/tools/kernel/sc16is7xx_mod_build.sh

chmod +x sc16is7xx_mod_build.sh
./sc16is7xx_mod_build.sh
```

---

## 🔍 Debugging

Run with trace:

```bash
bash -x ./<script>.sh
```

Check if module was created:

```bash
find . -name '*.ko'
```

---

## ⚠️ Notes

* Use **RAW GitHub URLs** (`raw.githubusercontent.com`), not `/blob/`
* Some drivers may already be part of the kernel:

```bash
modinfo <driver>
```

If present:

```bash
sudo modprobe <driver>
```

---

## 💡 Recommendation

For development, prefer cloning the full repository:

```bash
git clone https://github.com/be-iis/be-iis-installer.git
cd be-iis-installer
```

This ensures all dependencies and scripts are consistent.

