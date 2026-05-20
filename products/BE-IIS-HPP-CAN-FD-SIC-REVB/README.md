# BE-IIS HPP CAN FD SIC

CAN FD HAT for Raspberry Pi with MCP2518FD and TCAN1472 SIC transceiver.

## Features

- CAN FD up to 8 MBit/s
- Classic CAN support
- MCP2518FD SPI CAN controller
- TCAN1472 SIC transceiver
- Raspberry Pi HAT++
- Stackable BE-IIS HAT++ system
- Raspberry Pi 2 / 3 / 4 / 5
- Raspberry Pi Zero / Zero 2 W

## Resources

- [Datasheet](https://www.be-iis.eu/products/BE-IIS-HPP-CAN_B/datasheet.pdf)
- [Schematic](https://www.be-iis.eu/products/BE-IIS-HPP-CAN_B/schematic.pdf)
- [3D Model](https://www.be-iis.eu/products/BE-IIS-HPP-CAN_B/model.zip)
- [Interactive BOM](https://www.be-iis.eu/products/BE-IIS-HPP-CAN_B/ibom.html)

## Software

Device Tree overlays and test scripts are included in this repository.

Overlay source:

```text
overlays/raspberry-pi/be-iis-hpp-can/
```

Test scripts:

```text
products/BE-IIS-HPP-CAN-FD-SIC/scripts/
```

Production test:

```text
products/BE-IIS-HPP-CAN-FD-SIC/test/
```

## Example

Configure CAN-FD 8 MBit:

```sh
./config_8M_can.sh
```

CAN-FD TX test:

```sh
./canperf.py tx -i beiis-can0 --size 64 --time 10
```

## Notes

- ~3.5 MBit/s effective CAN-FD payload throughput is realistic on Raspberry Pi with MCP2518FD over SPI
- `IRQ_TYPE_LEVEL_LOW` is required
- `IRQ_TYPE_EDGE_FALLING` is not stable
- Raspberry Pi 5 may require explicit IRQ pinctrl assignment
- DigiKey link: later

## Company

Brechel Electronic  
Industrial Interface Systems

🌐 https://www.be-iis.eu

