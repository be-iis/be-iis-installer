# CAN-Gateway-Testbench v0.1

## Aufbau mit vier Raspberry Pis

```text
Pi 1: Testbench Master
  can0
   │
   │ CAN-Segment A
   │
Pi 2: Transparentes Gateway
   ║
   ║ TCP-Verbindung des Gateways
   ║
Pi 3: Transparentes Gateway
   │
   │ CAN-Segment B
   │
  can0
Pi 4: Testbench Slave

Pi 1 ........................ WLAN-Steuerverbindung ........................ Pi 4
```

Die WLAN-Verbindung transportiert nur Start-/Stop-Kommandos und Messergebnisse.
Alle eigentlichen Prüfframes laufen über CAN, Pi 2, die Gateway-TCP-Verbindung,
Pi 3 und den zweiten CAN-Bus.

## Gemessene Tests

Der Master führt automatisch vier Tests aus:

1. **Round-Trip-Ping:** Pi 1 sendet einen Frame, Pi 4 spiegelt ihn sofort zurück.
   Gemessen werden Verlust, Duplikate und RTT mit Mittelwert, Median, p95, p99
   und Maximum.
2. **Vorwärts:** Pi 1 → Pi 4. Pi 4 wertet Sequenznummern und Payload aus.
3. **Rückwärts:** Pi 4 → Pi 1. Pi 1 wertet den Datenstrom aus.
4. **Bidirektional:** Beide Seiten senden gleichzeitig. Beide Richtungen werden
   getrennt bewertet.

Ausgewertet werden:

- gesendete und eindeutig empfangene Frames
- Verlustquote
- Duplikate
- Reihenfolgefehler
- Payload-/Korruptionsfehler
- Frame- und Payload-Durchsatz
- Round-Trip-Latenz und Streuung

## Voraussetzungen

- Linux mit SocketCAN auf Pi 1 und Pi 4
- CAN-Interfaces bereits vollständig konfiguriert und `UP`
- Python 3.11 oder neuer empfohlen
- keine externen Python-Pakete
- Pi 1 muss Pi 4 über WLAN/TCP-Port `29600` erreichen

Das Programm verändert Bitrate, Sample-Point, CAN-FD-Datenbitrate oder
Terminierung nicht.

## Komplette Startreihenfolge

Beispieladressen:

- Pi 2 Gateway-Link: `192.168.10.2`
- Pi 3 Gateway-Link: `192.168.10.3`
- Pi 4 WLAN: `192.168.50.44`

1. Alle vier CAN-Interfaces müssen bereits mit identischen Parametern pro
   Segment aktiv sein. Beispiel für klassisches CAN mit 500 kbit/s:

   ```bash
   sudo ip link set can0 down 2>/dev/null || true
   sudo ip link set can0 type can bitrate 500000 restart-ms 100
   sudo ip link set can0 up
   ```

2. Transparentes Gateway auf Pi 2 starten:

   ```bash
   ./can_tcp_bridge.py 192.168.10.3 can0
   ```

3. Transparentes Gateway auf Pi 3 starten:

   ```bash
   ./can_tcp_bridge.py 192.168.10.2 can0
   ```

4. Testbench-Slave auf Pi 4 starten.
5. Testsuite auf Pi 1 starten.

Pi 1 und Pi 4 dürfen über WLAN verbunden sein. Die Gateways Pi 2 und Pi 3
können ihre eigene, davon unabhängige TCP-Verbindung verwenden.

## Start auf Pi 4

```bash
cd can-gateway-testbench
./can_gateway_testbench.py slave --can can0
```

Optional nur an die WLAN-IP binden:

```bash
./can_gateway_testbench.py slave \
  --can can0 \
  --control-bind 192.168.50.44
```

## Tests auf Pi 1 starten

Beispiel: Pi 4 hat über WLAN die Adresse `192.168.50.44`.

```bash
cd can-gateway-testbench
./can_gateway_testbench.py master \
  --can can0 \
  --slave 192.168.50.44
```

Standardwerte:

- 1.000 Ping-Frames mit 100 Frames/s
- 5.000 Frames je Streamtest mit 500 Frames/s
- klassische CAN-Frames mit 8 Byte
- CAN-Basis-ID `0x600`

## Schneller Funktionstest

```bash
./can_gateway_testbench.py master \
  --can can0 \
  --slave 192.168.50.44 \
  --ping-count 100 \
  --count 500 \
  --ping-rate 50 \
  --rate 200
```

## Belastungstest

Die Sendrate `0` bedeutet: so schnell senden, wie SocketCAN und der Bus es
zulassen.

```bash
./can_gateway_testbench.py master \
  --can can0 \
  --slave 192.168.50.44 \
  --ping-count 5000 \
  --count 100000 \
  --ping-rate 500 \
  --rate 0 \
  --settle 5
```

Bei einem ungebremsten Test können erwartungsgemäß CAN-Controller-Queues oder
Gateway-Puffer überlaufen. Deshalb zunächst mit einer konservativen Rate testen.

## CAN FD

Beide CAN-Segmente und beide Gateways müssen dafür bereits für CAN FD
konfiguriert sein.

```bash
./can_gateway_testbench.py master \
  --can can0 \
  --slave 192.168.50.44 \
  --fd \
  --brs \
  --payload-length 64 \
  --rate 1000
```

Pi 4 benötigt keine zusätzlichen FD-Argumente. Der Master übermittelt die
Testparameter über die WLAN-Steuerverbindung.

## CAN-IDs

Standardmäßig werden diese IDs verwendet:

| Funktion | CAN-ID |
|---|---:|
| Ping-Anfrage | `0x600` |
| Ping-Antwort | `0x601` |
| Vorwärtsstrom | `0x610` |
| Rückwärtsstrom | `0x611` |
| Bidirektional Pi 1 → Pi 4 | `0x620` |
| Bidirektional Pi 4 → Pi 1 | `0x621` |

Mit `--base-id 0x500` verschiebt sich der komplette Block entsprechend. Auf
Pi 1 und Pi 4 muss derselbe Wert verwendet werden.

## Automatische PASS/FAIL-Auswertung

Standardmäßig gilt ein Test nur dann als bestanden, wenn es keine Verluste,
Duplikate, Reihenfolgefehler, Payload-Fehler oder lokalen Sendefehler gibt. Der
Master beendet sich bei einem fehlgeschlagenen Kriterium mit Exit-Code `1`.

Grenzen können explizit gesetzt werden:

```bash
./can_gateway_testbench.py master \
  --can can0 \
  --slave 192.168.50.44 \
  --max-loss-percent 0.1 \
  --max-duplicates 0 \
  --max-out-of-order 0 \
  --max-payload-errors 0 \
  --max-p95-rtt-ms 20
```

Mit `--no-fail-exit` wird der Bericht weiterhin als FAIL markiert, das Programm
liefert für manuelle Versuche aber Exit-Code `0`.

## Ergebnisdateien

Der Master erzeugt standardmäßig:

```text
results/YYYYMMDD-HHMMSS/
├── report.html
├── summary.json
├── summary.csv
└── ping_samples.csv
```

- `report.html`: direkt lesbarer Gesamtbericht mit RTT-Histogramm
- `summary.json`: vollständige maschinenlesbare Ergebnisse und Konfiguration
- `summary.csv`: eine Zeile pro Test/Richtung
- `ping_samples.csv`: jeder einzelne RTT-Messwert

Ein festes, noch nicht vorhandenes Zielverzeichnis kann mit `--output`
angegeben werden.

## systemd auf Pi 4

Die mitgelieferte Service-Datei setzt eine Installation unter
`/opt/can-gateway-testbench` voraus:

```bash
sudo mkdir -p /opt/can-gateway-testbench
sudo cp can_gateway_testbench.py /opt/can-gateway-testbench/
sudo cp can-gateway-testbench-slave.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now can-gateway-testbench-slave.service
```

Status prüfen:

```bash
systemctl status can-gateway-testbench-slave.service
journalctl -u can-gateway-testbench-slave.service -f
```

## Selbsttest der Software

```bash
python3 -m unittest -v test_can_gateway_testbench.py
```

Die Tests prüfen Frame- und Payload-Codierung, Korruptionserkennung,
Sequenzstatistik, Perzentile, Berichtserzeugung sowie einen vollständigen
Master/Slave-Lauf über einen simulierten CAN-Link.

## Sicherheit

Der Steuerport hat in v0.1 keine Authentifizierung oder Verschlüsselung. Er
sollte nur in einem vertrauenswürdigen Test-WLAN erreichbar sein.
