# Lokale CAN-Gateway-Testbench v0.2

Diese Variante läuft direkt auf den beiden Gateway-Pis. Pi 1 und Pi 4 werden
für den Funktionstest nicht benötigt.

```text
Pi 2
  can_tcp_bridge.py
  can_gateway_local_testbench.py run
          │
          │ SocketCAN can0 oder vcan0
          ▼
     Gateway A  ===== TCP =====  Gateway B
                                  ▲
                                  │ SocketCAN can0 oder vcan0
Pi 3                              │
  can_tcp_bridge.py
  can_gateway_local_testbench.py responder

Pi 2 ------------- separate TCP-Steuerverbindung ------------- Pi 3
```

Die Testbench erzeugt echte SocketCAN-Frames auf dem Gateway-Pi. Das lokal
laufende Gateway empfängt diese Frames wie die Frames einer anderen
SocketCAN-Anwendung, überträgt sie per TCP und sendet sie auf dem CAN-Interface
der Gegenseite aus.

## Gemessene Tests

1. Round-Trip-Ping: Runner → Gateway → Responder → Gateway → Runner
2. Vorwärtsdatenstrom
3. Rückwärtsdatenstrom
4. Gleichzeitiger bidirektionaler Datenstrom

Ausgewertet werden Verlust, Duplikate, Reihenfolgefehler, beschädigte Payload,
Sendefehler, Durchsatz sowie RTT-Minimum, Mittelwert, Median, p95, p99,
Maximum und Standardabweichung.

## Wichtig: CAN-ACK bei nur einem Controller

Testbench und Gateway sind zwei Programme, aber sie verwenden denselben
physischen CAN-Controller. Sie sind daher nicht zwei elektrische CAN-Knoten und
können sich nicht gegenseitig im ACK-Slot bestätigen.

Für einen lokalen Zwei-Pi-Test gibt es drei sinnvolle Varianten:

### Variante A: vcan – empfohlen für den ersten Softwaretest

Hier wird der komplette Python-/SocketCAN-/TCP-Datenpfad getestet, aber nicht
der physische CAN-Controller oder Transceiver.

Auf beiden Gateway-Pis:

```bash
sudo modprobe vcan
sudo ip link add vcan0 type vcan 2>/dev/null || true
sudo ip link set vcan0 up
ip -details link show vcan0
```

Danach Gateway und Testbench jeweils mit `vcan0` starten.

### Variante B: Controller-Loopback

Damit wird zusätzlich der reale CAN-Treiber und, abhängig vom Controller, ein
Teil des Controllers getestet. Der physische CAN-Bus und Transceiver werden
nicht geprüft.

Classic CAN:

```bash
sudo ip link set can0 down 2>/dev/null || true
sudo ip link set can0 type can \
    bitrate 500000 \
    loopback on \
    restart-ms 100
sudo ip link set can0 up
```

CAN FD:

```bash
sudo ip link set can0 down 2>/dev/null || true
sudo ip link set can0 type can \
    bitrate 500000 \
    dbitrate 2000000 \
    fd on \
    loopback on \
    restart-ms 100
sudo ip link set can0 up
```

Nicht jeder CAN-Treiber unterstützt den Controller-Loopback-Modus.

### Variante C: normaler physischer CAN-Bus

Im normalen Modus muss auf jedem CAN-Segment mindestens ein weiterer aktiver
CAN-Controller vorhanden sein, der Frames bestätigt. Alternativ kann ein
Controller/Treiber mit `presume-ack` verwendet werden:

```bash
sudo ip link set can0 down
sudo ip link set can0 type can \
    bitrate 500000 \
    presume-ack on \
    restart-ms 100
sudo ip link set can0 up
```

`presume-ack` wird nicht von jedem Treiber unterstützt. Ohne einen zweiten
physischen CAN-Knoten, Controller-Loopback oder `presume-ack` bleibt ein Frame
wegen des fehlenden ACKs in der CAN-Retransmission hängen.

## Schnellstart mit vcan

Beispiel:

- Pi 2: `10.10.10.2`
- Pi 3: `10.10.10.3`
- Gateway-Port: Standardwert des Gateway-Programms
- Testbench-Steuerport: `29600`

### 1. vcan auf beiden Pis anlegen

```bash
sudo modprobe vcan
sudo ip link add vcan0 type vcan 2>/dev/null || true
sudo ip link set vcan0 up
```

### 2. Gateway auf Pi 2 starten

```bash
./can_tcp_bridge.py 10.10.10.3 vcan0
```

### 3. Gateway auf Pi 3 starten

```bash
./can_tcp_bridge.py 10.10.10.2 vcan0
```

### 4. Responder auf Pi 3 starten

```bash
./can_gateway_local_testbench.py responder \
    --can vcan0 \
    --control-bind 10.10.10.3
```

### 5. Test auf Pi 2 starten

```bash
./can_gateway_local_testbench.py run \
    --can vcan0 \
    --peer 10.10.10.3
```

## Kurzer Funktionstest

```bash
./can_gateway_local_testbench.py run \
    --can vcan0 \
    --peer 10.10.10.3 \
    --ping-count 100 \
    --count 500 \
    --ping-rate 50 \
    --rate 200
```

## CAN-FD-Test

Das funktioniert mit `vcan0` oder einem passend konfigurierten CAN-FD-Interface:

```bash
./can_gateway_local_testbench.py run \
    --can vcan0 \
    --peer 10.10.10.3 \
    --fd \
    --brs \
    --payload-length 64 \
    --ping-count 1000 \
    --count 10000 \
    --rate 1000
```

Bei `vcan` hat das BRS-Flag keine physikalische Geschwindigkeitswirkung. Es
prüft aber, ob das Flag und die CAN-FD-Frames korrekt durch das Gateway
übertragen werden.

## Ergebnisdateien

Der Runner erzeugt:

```text
results/YYYYMMDD-HHMMSS/
├── report.html
├── summary.json
├── summary.csv
└── ping_samples.csv
```

## Alte Kommandonamen

Zur Kompatibilität funktionieren weiterhin:

```bash
./can_gateway_local_testbench.py slave ...
./can_gateway_local_testbench.py master --slave PEER ...
```

Die neuen Namen `responder`, `run` und `--peer` beschreiben den lokalen Aufbau
klarer.
