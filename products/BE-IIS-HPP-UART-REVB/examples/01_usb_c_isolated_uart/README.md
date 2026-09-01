# 01 – Test the isolated USB-C UART

Each BE-IIS-HPP-UART provides two additional UARTs:

| Port | Connector | Isolation |
| --- | --- | --- |
| `a` | USB-C | galvanically isolated |
| `b` | HAT header | not isolated |

## 1. On the Raspberry Pi

The HAT++ EEPROM assigns an instance name. List the UARTs **on the Raspberry
Pi**:

```bash
ls -l /dev/beiis-uart-*
```

For example, a HAT in instance IV appears as:

```text
/dev/beiis-uart-iv-a -> ttySC0
/dev/beiis-uart-iv-b -> ttySC1
```

Only the `beiis-uart-*` names are expected on the Raspberry Pi. Do **not**
look for `/dev/ttyUSB*` or `/dev/ttyACM*` there; those names appear on the
separate PC connected to the HAT's USB-C port.

Configure the isolated USB-C UART and send a message:

```bash
stty -F /dev/beiis-uart-iv-a 115200 raw -echo -ixon -ixoff
printf 'Hello from the Raspberry Pi via the isolated USB-C UART\r\n' > /dev/beiis-uart-iv-a
```

For another stack instance, substitute the corresponding device name:

```text
/dev/beiis-uart-i-a
/dev/beiis-uart-iv-a
/dev/beiis-uart-v-a
```

## 2. On the connected PC

Connect the HAT USB-C connector to a **separate PC** with a USB data cable.
The PC enumerates the HAT as a USB serial device. Find it **on that PC**:

```bash
ls -l /dev/ttyUSB* /dev/ttyACM*
```

Open the detected port at 115200 baud, for example:

```bash
picocom -b 115200 /dev/ttyUSB0
```

The message sent by the Pi must appear in `picocom`.

## 3. Test the reverse direction

Type a line in `picocom`. On the Raspberry Pi, receive it with:

```bash
cat /dev/beiis-uart-iv-a
```

Stop `cat` with `Ctrl+C`.
