#!/usr/bin/env python3
"""Local web control for the BE-IIS HPP SPE Noise Generator."""

from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse
import argparse
import json
import re
import subprocess

SYSFS_ROOT = Path("/sys/bus/i2c/devices")
DRIVER_NAME = "beiis-hpp-spe-noise"
PRODUCT_ROOT = Path(__file__).resolve().parents[2]
FIRMWARE_DIR = PRODUCT_ROOT / "firmware"
FLASH_SCRIPT = PRODUCT_ROOT / "tools" / "beiis-machxo2-load.sh"
BOOLEAN_FIELDS = {"output_enable", "dds_enable", "fm_enable"}
STATUS_FIELDS = (
    "component_id", "firmware_id", "generator", "output_enable",
    "amplitude", "pwm_reference", "dds_enable", "fm_enable",
)
FIRMWARE_UPDATE_ENABLED = False


def instance_id(device):
    prop = device / "of_node" / "be-iis,instance"
    try:
        value = prop.read_bytes()
    except OSError:
        return None
    return int.from_bytes(value[:4], byteorder="big") if len(value) >= 4 else None


def get_device(name):
    if not re.fullmatch(r"[0-9]+-[0-9a-fA-F]{4}", name):
        raise ValueError("Invalid device")
    device = SYSFS_ROOT / name
    try:
        if not device.is_dir() or (device / "driver").resolve().name != DRIVER_NAME:
            raise ValueError("Noise generator device is not available")
    except OSError as exc:
        raise ValueError(f"Cannot access device: {exc}") from exc
    return device


def devices():
    result = []
    for device in sorted(SYSFS_ROOT.glob("*-*")):
        try:
            if (device / "driver").resolve().name != DRIVER_NAME:
                continue
            result.append({
                "id": device.name,
                "address": "0x" + device.name.rsplit("-", 1)[1],
                "instance": instance_id(device),
            })
        except OSError:
            continue
    return result


def read_status(device):
    return {
        field: (device / field).read_text().strip()
        for field in STATUS_FIELDS
    }


def write_settings(device, values):
    for field, value in values.items():
        if field == "generator":
            if value not in ("null", "prn", "dds"):
                raise ValueError("Invalid generator")
        elif field in BOOLEAN_FIELDS:
            value = str(value)
            if value not in ("0", "1"):
                raise ValueError(f"Invalid value for {field}")
        elif field == "amplitude":
            if not isinstance(value, int) or not 0 <= value <= 4:
                raise ValueError("Software gain must be a stage from 0 to 4")
        elif field == "pwm_reference":
            if not isinstance(value, int) or not 0 <= value <= 1023:
                raise ValueError("Hardware gain must be 0..1023")
        else:
            raise ValueError(f"Unsupported setting: {field}")
        (device / field).write_text(f"{value}\n")


def firmware_files():
    if not FIRMWARE_DIR.is_dir():
        return []
    return sorted(file.name for file in FIRMWARE_DIR.glob("*.bin") if file.is_file())


def program_firmware(device, filename):
    if not FIRMWARE_UPDATE_ENABLED:
        raise ValueError("Firmware update is disabled for this webtool instance")
    if instance_id(device) != 1:
        raise ValueError("Firmware update is available only for device instance I")
    if filename not in firmware_files():
        raise ValueError("Unknown firmware image")
    if not FLASH_SCRIPT.is_file():
        raise ValueError("MachXO2 flash script is not installed")

    result = subprocess.run(
        ["bash", str(FLASH_SCRIPT), str(FIRMWARE_DIR / filename)],
        text=True, capture_output=True, timeout=90, check=False,
    )
    output = (result.stdout + result.stderr).strip()
    if result.returncode:
        raise ValueError(output or "Firmware update failed")
    return output


PAGE = """<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>BE-IIS Noise Generator</title><style>
body{font-family:system-ui,sans-serif;max-width:680px;margin:2.5rem auto;padding:0 1.2rem;color:#182431}
h1{margin-bottom:.2rem}.card{border:1px solid #d8dee5;border-radius:10px;padding:1.25rem;margin-top:1rem}
label{display:block;margin:.8rem 0 .25rem}input[type=range]{width:100%}select{font:inherit;padding:.35rem;width:100%;box-sizing:border-box}
.check{display:flex;gap:.5rem;align-items:center}.check input{width:auto}small{color:#566575}#status,#flash_status{min-height:1.4rem;margin-top:1rem;color:#425466;white-space:pre-wrap}footer{margin-top:2rem;font-size:.9rem}a{color:#1265a8}button{font:inherit;padding:.45rem .8rem}
</style></head><body>
<h1>Noise Generator</h1><p>BE-IIS HPP SPE Noise Generator</p>
<div class="card"><label>Device<select id="device" onchange="selectDevice()"></select></label><small id="device_info"></small></div>
<div class="card">
<label>Generator<select id="generator" onchange="set('generator',this.value)"><option value="null">Off (null)</option><option value="prn">PRN noise</option><option value="dds">DDS</option></select></label>
<label class="check"><input id="output_enable" type="checkbox" onchange="setBool('output_enable',this)">Enable output</label>
<label>Hardware gain (PWM reference): <strong id="pwm_reference_value">0</strong><input id="pwm_reference" type="range" min="0" max="1023" oninput="pwm_reference_value.textContent=this.value" onchange="setNumber('pwm_reference',this)"></label>
<small>The six LEDs display this PWM hardware-gain value.</small>
<label>Software gain stage<select id="amplitude" onchange="setNumber('amplitude',this)"><option value="0">0 — 1× (0 dB)</option><option value="1">1 — 1/2 (−6 dB)</option><option value="2">2 — 1/4 (−12 dB)</option><option value="3">3 — 1/8 (−18 dB)</option><option value="4">4 — 1/16 (−24 dB)</option></select></label>
</div>
<div class="card"><h2>DDS / FM</h2>
<label class="check"><input id="dds_enable" type="checkbox" onchange="setBool('dds_enable',this)">Enable DDS</label>
<label class="check"><input id="fm_enable" type="checkbox" onchange="setBool('fm_enable',this)">Enable FM</label>
</div>
<div class="card" id="firmware_card" hidden><h2>Firmware update</h2>
<label>MachXO2 NVCM image<select id="firmware"></select></label>
<button onclick="flashFirmware()">Program instance I</button><small id="flash_hint"></small><p id="flash_status"></p>
</div>
<p id="status"></p><footer><span id="identity"></span> · <a href="https://www.be-iis.eu/" target="_blank" rel="noopener">www.be-iis.eu</a></footer>
<script>
let deviceList=[], firmwareEnabled=false;
async function request(path,data){const r=await fetch(path,{method:data?'POST':'GET',headers:{'Content-Type':'application/json'},body:data?JSON.stringify(data):undefined});const j=await r.json();if(!r.ok)throw Error(j.error);return j}
function current(){return device.value}
function display(s){generator.value=s.generator;output_enable.checked=s.output_enable==='1';amplitude.value=s.amplitude;pwm_reference.value=s.pwm_reference;pwm_reference_value.textContent=s.pwm_reference;dds_enable.checked=s.dds_enable==='1';fm_enable.checked=s.fm_enable==='1';identity.textContent='Component '+s.component_id+', firmware '+s.firmware_id}
async function set(field,value){try{const r=await request('/api/settings',{device:current(),values:{[field]:value}});display(r.status);status.textContent='Applied.'}catch(e){status.textContent='Error: '+e.message}}
function setBool(field,element){set(field,element.checked?'1':'0')}
function setNumber(field,element){set(field,Number(element.value))}
function selectedInfo(){return deviceList.find(d=>d.id===current())}
async function selectDevice(){const d=selectedInfo();device_info.textContent=d?'I²C '+d.address+' · instance '+(d.instance||'unknown'):'';await request('/api/status?device='+encodeURIComponent(current())).then(display).catch(e=>status.textContent='Error: '+e.message);const show=firmwareEnabled&&d&&d.instance===1;firmware_card.hidden=!show}
async function flashFirmware(){if(!confirm('Program MachXO2 NVCM of instance I with '+firmware.value+'?'))return;flash_status.textContent='Programming…';try{const r=await request('/api/firmware',{device:current(),firmware:firmware.value});flash_status.textContent=r.output}catch(e){flash_status.textContent='Error: '+e.message}}
async function load(){try{const r=await request('/api/devices');deviceList=r.devices;firmwareEnabled=r.firmware_update_enabled;device.innerHTML='';for(const d of deviceList){const o=document.createElement('option');o.value=d.id;o.textContent='Instance '+(d.instance||'?')+' · '+d.address;o.selected=d.instance===1;device.append(o)}if(!deviceList.length)throw Error('No noise generator device found');const f=await request('/api/firmware');firmware.innerHTML='';for(const name of f.files){const o=document.createElement('option');o.value=name;o.textContent=name;firmware.append(o)}flash_hint.textContent=f.enabled?'':'Firmware update disabled; start with --enable-firmware-update.';await selectDevice()}catch(e){status.textContent='Error: '+e.message}}
load()
</script></body></html>"""


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        print("%s - %s" % (self.address_string(), fmt % args))

    def send_json(self, status, payload):
        data = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        try:
            parsed = urlparse(self.path)
            if parsed.path == "/":
                data = PAGE.encode()
                self.send_response(200)
                self.send_header("Content-Type", "text/html; charset=utf-8")
                self.send_header("Content-Length", str(len(data)))
                self.end_headers()
                self.wfile.write(data)
            elif parsed.path == "/api/devices":
                self.send_json(200, {"devices": devices(),
                                     "firmware_update_enabled": FIRMWARE_UPDATE_ENABLED})
            elif parsed.path == "/api/status":
                name = parse_qs(parsed.query).get("device", [""])[0]
                self.send_json(200, read_status(get_device(name)))
            elif parsed.path == "/api/firmware":
                self.send_json(200, {"enabled": FIRMWARE_UPDATE_ENABLED,
                                     "files": firmware_files()})
            else:
                self.send_error(404)
        except (OSError, ValueError) as exc:
            self.send_json(500, {"error": str(exc)})

    def do_POST(self):
        if self.path not in ("/api/settings", "/api/firmware"):
            self.send_error(404)
            return
        try:
            size = int(self.headers.get("Content-Length", "0"))
            body = json.loads(self.rfile.read(size))
            if not isinstance(body, dict):
                raise ValueError("Request must be an object")
            device = get_device(body.get("device", ""))
            if self.path == "/api/settings":
                values = body.get("values")
                if not isinstance(values, dict):
                    raise ValueError("Settings must be an object")
                write_settings(device, values)
                self.send_json(200, {"status": read_status(device)})
            else:
                output = program_firmware(device, body.get("firmware", ""))
                self.send_json(200, {"output": output})
        except (OSError, ValueError, json.JSONDecodeError,
                subprocess.TimeoutExpired) as exc:
            self.send_json(400, {"error": str(exc)})


def main():
    global FIRMWARE_UPDATE_ENABLED
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", default="0.0.0.0")
    parser.add_argument("--port", type=int, default=8080)
    parser.add_argument("--enable-firmware-update", action="store_true",
                        help="allow NVCM programming through this web server")
    args = parser.parse_args()
    FIRMWARE_UPDATE_ENABLED = args.enable_firmware_update
    ThreadingHTTPServer((args.host, args.port), Handler).serve_forever()


if __name__ == "__main__":
    main()
