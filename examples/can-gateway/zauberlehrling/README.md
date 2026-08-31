# Der Zauberlehrling over CAN gateway

A human-readable long-payload test for the CAN-over-TCP bridge. The sender
splits Goethe's *Der Zauberlehrling* into ordinary 8-byte Classical CAN frames.

## Sender (Pi2)

```bash
python3 zauberlehrling_sender.py can0
```

## ASCII dump (Pi3)

```bash
candump -L -a can0,700:7FF
```

The `-a` option appends printable ASCII to every CAN frame. Both gateway
instances must be running; all CAN interfaces use the same bitrate.
