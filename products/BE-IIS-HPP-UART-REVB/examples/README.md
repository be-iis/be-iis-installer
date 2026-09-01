# BE-IIS-HPP-UART examples

## 01 – Test the isolated USB-C UART

Each BE-IIS-HPP-UART provides two additional UARTs:

| Port | Connector | Isolation |
| --- | --- | --- |
| `a` | USB-C | galvanically isolated |
| `b` | HAT header | not isolated |

The HAT++ EEPROM assigns an instance name. The currently supported isolated
USB-C UART devices are:

```text
/dev/beiis-uart-i-a
/dev/beiis-uart-iv-a
/dev/beiis-uart-v-a
```

Connect the USB-C connector of the HAT to a PC with a USB data cable. On the
PC, find the enumerated USB serial device:

```bash
ls -l /dev/ttyUSB* /dev/ttyACM*
```

Open it at 115200 baud, for example:

```bash
picocom -b 115200 /dev/ttyUSB0
```

On the Raspberry Pi, configure one of the isolated UARTs and send a message.
Use the device that matches the HAT++ instance in the stack:

```bash
stty -F /dev/beiis-uart-i-a 115200 raw -echo -ixon -ixoff
printf 'Hello from the Raspberry Pi via the isolated USB-C UART\r\n' > /dev/beiis-uart-i-a
```

For instance IV or V, use the corresponding device name:

```bash
stty -F /dev/beiis-uart-iv-a 115200 raw -echo -ixon -ixoff
printf 'Hello from the Raspberry Pi via the isolated USB-C UART\r\n' > /dev/beiis-uart-iv-a

stty -F /dev/beiis-uart-v-a 115200 raw -echo -ixon -ixoff
printf 'Hello from the Raspberry Pi via the isolated USB-C UART\r\n' > /dev/beiis-uart-v-a
```

The message must appear in the PC terminal. Communication is bidirectional.
To read characters sent by the PC, run on the Pi:

```bash
cat /dev/beiis-uart-i-a
```

Stop `cat` with `Ctrl+C`.
