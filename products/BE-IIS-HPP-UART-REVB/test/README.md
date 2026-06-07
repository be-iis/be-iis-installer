# BE-IIS-HPP-UART Usage Test

Simple UART communication test between a Raspberry Pi with **BE-IIS-HPP-UART** and a PC.

Default settings:

```text
115200 baud
8 data bits
no parity
1 stop bit
no flow control
```

---

## 1. Raspberry Pi

### 1.1 Check BE-IIS UART devices

```bash
ls -l /dev/beiis-uart-*
```

Example device names:

```text
/dev/beiis-uart-i-a
/dev/beiis-uart-i-b
/dev/beiis-uart-iv-a
/dev/beiis-uart-iv-b
```

The naming scheme is:

```text
/dev/beiis-uart-<hat-instance>-<port>
```

Examples:

```text
/dev/beiis-uart-i-a
/dev/beiis-uart-i-b
/dev/beiis-uart-iv-a
/dev/beiis-uart-iv-b
```

Use the port that matches your HAT++ instance.

---

### 1.2 Run the Python test script

The repository contains the test script:

```text
beiis_uart_test.py
```

Install the dependency:

```bash
sudo apt update
sudo apt install python3-serial
```

Run the test on port A:

```bash
python3 beiis_uart_test.py -d /dev/beiis-uart-i-a
```

Or use another detected port:

```bash
python3 beiis_uart_test.py -d /dev/beiis-uart-iv-a
```

Use another baudrate:

```bash
python3 beiis_uart_test.py -d /dev/beiis-uart-i-a -b 115200
```

Use another send interval:

```bash
python3 beiis_uart_test.py -d /dev/beiis-uart-i-a -i 0.5
```

The script sends cyclic test messages and prints all received data.

Example output:

```text
TX: BE-IIS UART test 0 @ 2026-06-07 20:45:00
RX: hello from PC
```

Stop the test with:

```text
Ctrl+C
```

---

## 2. PC with Linux

### 2.1 Find the USB-UART adapter

```bash
ls -l /dev/ttyUSB* /dev/ttyACM*
```

Example:

```text
/dev/ttyUSB0
```

---

### 2.2 Configure the PC UART port

```bash
stty -F /dev/ttyUSB0 115200 raw -echo
```

---

### 2.3 Receive data on Linux

```bash
cat /dev/ttyUSB0
```

Stop with:

```text
Ctrl+C
```

---

### 2.4 Send data from Linux

```bash
printf "hello from Linux PC\r\n" > /dev/ttyUSB0
```

---

### 2.5 Send cyclic test messages from Linux

```bash
while true; do
    printf "hello from Linux PC $(date '+%H:%M:%S')\r\n" > /dev/ttyUSB0
    sleep 1
done
```

Stop with:

```text
Ctrl+C
```

---

## 3. PC with Windows

On Windows, use a serial terminal program.

Recommended options:

```text
PuTTY
MobaXterm
Tera Term
```

Other tools such as HTerm or RealTerm also work.

---

### 3.1 Find the COM port

Open **Device Manager** and check the USB-UART adapter under:

```text
Ports (COM & LPT)
```

Example:

```text
COM5
```

---

### 3.2 Serial settings

Use these settings:

```text
Port:       COM5
Baudrate:   115200
Data bits:  8
Parity:     None
Stop bits:  1
Flow ctrl:  None
Line ending: CR+LF recommended
```

---

### 3.3 PuTTY

1. Select **Serial**
2. Enter the COM port, for example `COM5`
3. Set speed to `115200`
4. Open the connection

---

### 3.4 MobaXterm

1. Start a new **Session**
2. Select **Serial**
3. Select the COM port, for example `COM5`
4. Set speed to `115200`
5. Open the session

---

### 3.5 Tera Term

1. Select **Serial**
2. Select the COM port, for example `COM5`
3. Set the serial port settings to `115200 8N1`
4. Disable flow control

---

### 3.6 Send and receive data on Windows

Start the Python test script on the Raspberry Pi:

```bash
python3 beiis_uart_test.py -d /dev/beiis-uart-i-a
```

Then type a message in the Windows terminal, for example:

```text
hello from Windows
```

The Raspberry Pi should print the received message.

The Windows terminal should also receive the cyclic test messages from the Raspberry Pi.

---

## 4. Wiring

Connect TX and RX crossed:

```text
PC USB-UART TX  -> BE-IIS UART RX
PC USB-UART RX  -> BE-IIS UART TX
GND             -> GND
```

Do not connect TX to TX.

Make sure the voltage levels are compatible.

---

## 5. Notes

Use the BE-IIS device names on the Raspberry Pi instead of the Linux kernel names.

Recommended:

```text
/dev/beiis-uart-i-a
/dev/beiis-uart-i-b
/dev/beiis-uart-iv-a
/dev/beiis-uart-iv-b
```

Avoid using directly:

```text
/dev/ttySC0
/dev/ttySC1
```

Linux kernel names like `ttySC0` and `ttySC1` may change when multiple serial devices are present.
