#!/usr/bin/env python3
"""Local web control for the BE-IIS HPP SPE Noise Generator."""

from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse
import argparse
import json
import re
import subprocess
import threading

SYSFS_ROOT = Path("/sys/bus/i2c/devices")
DRIVER_NAME = "beiis-hpp-spe-noise"
PRODUCT_ROOT = Path(__file__).resolve().parents[2]
FIRMWARE_DIR = PRODUCT_ROOT / "firmware"
FLASH_SCRIPT = PRODUCT_ROOT / "tools" / "beiis-machxo2-load.sh"
BOOLEAN_FIELDS = {"output_enable", "dds_enable", "fm_enable"}
STATUS_FIELDS = (
    "component_id", "firmware_id", "generator", "output_enable",
    "pwm_reference", "dds_enable", "fm_enable",
)
FREQUENCY_FIELDS = {"dds_frequency_hz", "fm_frequency_hz"}
MAX_FREQUENCY_HZ = 15_999_998
SETTINGS_LOCK = threading.RLock()
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
    with SETTINGS_LOCK:
        result = {field: (device / field).read_text().strip()
                  for field in STATUS_FIELDS}
        for field in FREQUENCY_FIELDS:
            try:
                result[field] = (device / field).read_text().strip()
            except FileNotFoundError:
                result[field] = None  # Older driver: keep other controls usable.
        return result


def write_settings(device, values):
    # Validate the complete request before performing any device writes.
    checked = {}
    for field, value in values.items():
        if field == "generator":
            if value not in ("null", "prn", "dds"):
                raise ValueError("Invalid generator")
        elif field in BOOLEAN_FIELDS:
            value = str(value)
            if value not in ("0", "1"):
                raise ValueError(f"Invalid value for {field}")
        elif field == "pwm_reference":
            if type(value) is not int or not 0 <= value <= 1023:
                raise ValueError("Hardware gain must be 0..1023")
        elif field in FREQUENCY_FIELDS:
            if type(value) is not int or not 0 <= value <= MAX_FREQUENCY_HZ:
                raise ValueError(f"Frequency must be an integer from 0 to {MAX_FREQUENCY_HZ} Hz")
            if not (device / field).exists():
                raise ValueError("Update the noise generator kernel driver to enable frequency control")
        else:
            raise ValueError(f"Unsupported setting: {field}")
        checked[field] = value
    with SETTINGS_LOCK:
        for field, value in checked.items():
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
label{display:block;margin:.8rem 0 .25rem}input[type=range]{width:100%}input[type=number]{font:inherit;padding:.4rem;width:12rem;max-width:100%;box-sizing:border-box}.steps{display:flex;gap:.4rem;flex-wrap:wrap;margin:.7rem 0}.steps button{flex:1;min-width:3rem}.frequency{display:flex;gap:.5rem;align-items:center;flex-wrap:wrap}button:disabled,input:disabled{opacity:.5}select{font:inherit;padding:.35rem;width:100%;box-sizing:border-box}
.check{display:flex;gap:.5rem;align-items:center}.check input{width:auto}small{color:#566575}#status,#flash_status{min-height:1.4rem;margin-top:1rem;color:#425466;white-space:pre-wrap}footer{margin-top:2rem;font-size:.9rem}a{color:#1265a8}button{font:inherit;padding:.45rem .8rem}
</style></head><body>
<h1>Noise Generator</h1><p>BE-IIS HPP SPE Noise Generator</p>
<div class="card"><label>Device<select id="device" onchange="selectDevice()"></select></label><small id="device_info"></small></div>
<div class="card">
<label>Generator<select id="generator" onchange="set('generator',this.value)"><option value="null">Off (null)</option><option value="prn">PRN noise</option><option value="dds">DDS</option></select></label>
<label class="check"><input id="output_enable" type="checkbox" onchange="setBool('output_enable',this)">Enable output</label>
<label>Hardware gain (PWM reference): <strong id="pwm_reference_value">0</strong><input id="pwm_reference" type="range" min="0" max="1023" oninput="pwm_reference_value.textContent=this.value" onchange="setNumber('pwm_reference',this)"></label>
<div class="steps" role="group" aria-label="Hardware gain steps">
<button type="button" onclick="stepPWM(-100)" title="−100" aria-label="Decrease hardware gain by 100">−−−</button>
<button type="button" onclick="stepPWM(-10)" title="−10" aria-label="Decrease hardware gain by 10">−−</button>
<button type="button" onclick="stepPWM(-1)" title="−1" aria-label="Decrease hardware gain by 1">−</button>
<button type="button" onclick="stepPWM(1)" title="+1" aria-label="Increase hardware gain by 1">+</button>
<button type="button" onclick="stepPWM(10)" title="+10" aria-label="Increase hardware gain by 10">++</button>
<button type="button" onclick="stepPWM(100)" title="+100" aria-label="Increase hardware gain by 100">+++</button>
</div><small>Steps: −100 / −10 / −1 / +1 / +10 / +100. Range: 0–1023.<br>The six LEDs display this PWM hardware-gain value.</small>
</div>
<div class="card"><h2>DDS / FM</h2>
<label class="check"><input id="dds_enable" type="checkbox" onchange="setBool('dds_enable',this)">Enable DDS</label>
<label class="check"><input id="fm_enable" type="checkbox" onchange="setBool('fm_enable',this)">Enable FM</label>
<form onsubmit="event.preventDefault();setFrequency('dds_frequency_hz')">
<label for="dds_frequency_hz">DDS carrier frequency (Hz)</label>
<div class="frequency"><input id="dds_frequency_hz" type="number" min="0" max="15999998" step="1" required><button id="dds_frequency_hz_apply" type="submit">Apply DDS</button></div></form>
<form onsubmit="event.preventDefault();setFrequency('fm_frequency_hz')">
<label for="fm_frequency_hz">FM modulation frequency (Hz)</label>
<div class="frequency"><input id="fm_frequency_hz" type="number" min="0" max="15999998" step="1" required><button id="fm_frequency_hz_apply" type="submit">Apply FM</button></div></form>
<p><small id="frequency_hint">Frequency resolution: approximately 1.91 Hz. The nearest available frequency is applied. Changing frequency briefly pauses DDS; FM depth stays unchanged.</small></p>
</div>
<div class="card" id="firmware_card" hidden><h2>Firmware update</h2>
<label>MachXO2 NVCM image<select id="firmware"></select></label>
<button onclick="flashFirmware()">Program instance I</button><small id="flash_hint"></small><p id="flash_status"></p>
</div>
<p id="status"></p><footer><span id="identity"></span> · <a href="https://www.be-iis.eu/" target="_blank" rel="noopener">www.be-iis.eu</a></footer>
<script>
const $=id=>document.getElementById(id);
let deviceList=[], firmwareEnabled=false, settingsQueue=Promise.resolve(), pendingSettings=0;
let selectionVersion=0;
async function request(path,data){const r=await fetch(path,{method:data?'POST':'GET',headers:{'Content-Type':'application/json'},body:data?JSON.stringify(data):undefined});const j=await r.json();if(!r.ok)throw Error(j.error);return j}
function current(){return $('device').value}
function display(s){
  $('generator').value=s.generator;
  $('output_enable').checked=s.output_enable==='1';
  $('pwm_reference').value=s.pwm_reference;
  $('pwm_reference_value').textContent=s.pwm_reference;
  $('dds_enable').checked=s.dds_enable==='1';
  $('fm_enable').checked=s.fm_enable==='1';
  for(const field of ['dds_frequency_hz','fm_frequency_hz']){
    const available=s[field]!=null;
    $(field).disabled=!available;$(field+'_apply').disabled=!available;
    $(field).value=available?s[field]:'';
  }
  $('frequency_hint').textContent=s.dds_frequency_hz==null||s.fm_frequency_hz==null
    ?'Update and reload the noise generator kernel driver to enable frequency control.'
    :'Frequency resolution: approximately 1.91 Hz. Applied values are shown rounded to whole Hz. Changing frequency briefly pauses DDS; FM depth stays unchanged.';
  $('identity').textContent='Component '+s.component_id+', firmware '+s.firmware_id;
}
function set(field,value){
  const target=current();if(!target)return;
  pendingSettings++;$('device').disabled=true;$('status').textContent='Applying…';
  settingsQueue=settingsQueue.then(async()=>{
    try{
      const r=await request('/api/settings',{device:target,values:{[field]:value}});
      if(pendingSettings===1&&current()===target){display(r.status);$('status').textContent='Applied.'}
    }catch(e){
      $('status').textContent='Error: '+e.message;
      if(pendingSettings===1&&current()===target){
        try{display(await request('/api/status?device='+encodeURIComponent(target)))}catch(_){}
      }
    }finally{pendingSettings--;if(!pendingSettings)$('device').disabled=false}
  });
  return settingsQueue;
}
function setBool(field,element){return set(field,element.checked?'1':'0')}
function setNumber(field,element){return set(field,Number(element.value))}
function stepPWM(delta){
  const element=$('pwm_reference');
  const value=Math.max(0,Math.min(1023,Number(element.value)+delta));
  element.value=value;$('pwm_reference_value').textContent=value;
  return set('pwm_reference',value);
}
function setFrequency(field){const input=$(field);if(input.reportValidity())return setNumber(field,input)}
function selectedInfo(){return deviceList.find(d=>d.id===current())}
async function selectDevice(){
  const version=++selectionVersion,d=selectedInfo();
  $('device_info').textContent=d?'I²C '+d.address+' · instance '+(d.instance||'unknown'):'';
  try{const s=await request('/api/status?device='+encodeURIComponent(current()));if(version===selectionVersion)display(s)}
  catch(e){if(version===selectionVersion)$('status').textContent='Error: '+e.message}
  $('firmware_card').hidden=!(firmwareEnabled&&d&&d.instance===1);
}
async function flashFirmware(){if(!confirm('Program MachXO2 NVCM of instance I with '+firmware.value+'?'))return;flash_status.textContent='Programming…';try{const r=await request('/api/firmware',{device:current(),firmware:firmware.value});flash_status.textContent=r.output}catch(e){flash_status.textContent='Error: '+e.message}}
async function load(){try{const r=await request('/api/devices');deviceList=r.devices;firmwareEnabled=r.firmware_update_enabled;device.innerHTML='';for(const d of deviceList){const o=document.createElement('option');o.value=d.id;o.textContent='Instance '+(d.instance||'?')+' · '+d.address;o.selected=d.instance===1;device.append(o)}if(!deviceList.length)throw Error('No noise generator device found');const f=await request('/api/firmware');firmware.innerHTML='';for(const name of f.files){const o=document.createElement('option');o.value=name;o.textContent=name;firmware.append(o)}flash_hint.textContent=f.enabled?'':'Firmware update disabled; start with --enable-firmware-update.';await selectDevice()}catch(e){$('status').textContent='Error: '+e.message}}
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
