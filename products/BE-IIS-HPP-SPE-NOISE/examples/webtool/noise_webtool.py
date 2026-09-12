#!/usr/bin/env python3
"""Local web control for the BE-IIS HPP SPE Noise Generator."""

from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import argparse
import json

SYSFS = Path("/sys/bus/i2c/devices/1-002a")
BOOLEAN_FIELDS = {"output_enable", "dds_enable", "fm_enable"}
STATUS_FIELDS = (
    "component_id", "firmware_id", "generator", "output_enable",
    "amplitude", "pwm_reference", "dds_enable", "fm_enable",
)


def read_status():
    return {field: (SYSFS / field).read_text().strip() for field in STATUS_FIELDS}


def write_settings(values):
    for field, value in values.items():
        if field == "generator":
            if value not in ("null", "prn", "dds"):
                raise ValueError("Invalid generator")
        elif field in BOOLEAN_FIELDS:
            value = str(value)
            if value not in ("0", "1"):
                raise ValueError(f"Invalid value for {field}")
        elif field == "amplitude":
            if not isinstance(value, int) or not 0 <= value <= 255:
                raise ValueError("Amplitude must be 0..255")
        elif field == "pwm_reference":
            if not isinstance(value, int) or not 0 <= value <= 1023:
                raise ValueError("Hardware gain must be 0..1023")
        else:
            raise ValueError(f"Unsupported setting: {field}")
        (SYSFS / field).write_text(f"{value}\n")


PAGE = """<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>BE-IIS Noise Generator</title><style>
body{font-family:system-ui,sans-serif;max-width:680px;margin:2.5rem auto;padding:0 1.2rem;color:#182431}
h1{margin-bottom:.2rem}.card{border:1px solid #d8dee5;border-radius:10px;padding:1.25rem;margin-top:1rem}
label{display:block;margin:.8rem 0 .25rem}input[type=range]{width:100%}select,input[type=number]{font:inherit;padding:.35rem;width:100%;box-sizing:border-box}
.check{display:flex;gap:.5rem;align-items:center}.check input{width:auto}small{color:#566575}#status{min-height:1.4rem;margin-top:1rem;color:#425466}footer{margin-top:2rem;font-size:.9rem}a{color:#1265a8}
</style></head><body>
<h1>Noise Generator</h1><p>BE-IIS HPP SPE Noise Generator</p>
<div class="card">
<label>Generator<select id="generator" onchange="set('generator',this.value)"><option value="null">Off (null)</option><option value="prn">PRN noise</option><option value="dds">DDS</option></select></label>
<label class="check"><input id="output_enable" type="checkbox" onchange="setBool('output_enable',this)">Enable output</label>
<label>Software gain / amplitude: <strong id="amplitude_value">0</strong><input id="amplitude" type="range" min="0" max="255" onchange="setNumber('amplitude',this)"></label>
<small>The LEDs display the software-amplitude value.</small>
<label>Hardware gain (PWM reference)<input id="pwm_reference" type="number" min="0" max="1023" onchange="setNumber('pwm_reference',this)"></label>
</div>
<div class="card"><h2>DDS / FM</h2>
<label class="check"><input id="dds_enable" type="checkbox" onchange="setBool('dds_enable',this)">Enable DDS</label>
<label class="check"><input id="fm_enable" type="checkbox" onchange="setBool('fm_enable',this)">Enable FM</label>
</div>
<p id="status"></p><footer><span id="identity"></span> · <a href="https://www.be-iis.eu/" target="_blank" rel="noopener">www.be-iis.eu</a></footer>
<script>
async function request(path,data){const r=await fetch(path,{method:data?'POST':'GET',headers:{'Content-Type':'application/json'},body:data?JSON.stringify(data):undefined});const j=await r.json();if(!r.ok)throw Error(j.error);return j}
function display(s){generator.value=s.generator;output_enable.checked=s.output_enable==='1';amplitude.value=s.amplitude;amplitude_value.textContent=s.amplitude;pwm_reference.value=s.pwm_reference;dds_enable.checked=s.dds_enable==='1';fm_enable.checked=s.fm_enable==='1';identity.textContent='Component '+s.component_id+', firmware '+s.firmware_id}
async function set(field,value){try{const r=await request('/api/settings',{[field]:value});display(r.status);status.textContent='Applied.'}catch(e){status.textContent='Error: '+e.message}}
function setBool(field,element){set(field,element.checked?'1':'0')}
function setNumber(field,element){set(field,Number(element.value))}
request('/api/status').then(display).catch(e=>status.textContent='Error: '+e.message)
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
            if self.path == "/":
                data = PAGE.encode()
                self.send_response(200)
                self.send_header("Content-Type", "text/html; charset=utf-8")
                self.send_header("Content-Length", str(len(data)))
                self.end_headers()
                self.wfile.write(data)
            elif self.path == "/api/status":
                self.send_json(200, read_status())
            else:
                self.send_error(404)
        except OSError as exc:
            self.send_json(500, {"error": str(exc)})

    def do_POST(self):
        if self.path != "/api/settings":
            self.send_error(404)
            return
        try:
            size = int(self.headers.get("Content-Length", "0"))
            values = json.loads(self.rfile.read(size))
            if not isinstance(values, dict):
                raise ValueError("Settings must be an object")
            write_settings(values)
            self.send_json(200, {"status": read_status()})
        except (ValueError, json.JSONDecodeError) as exc:
            self.send_json(400, {"error": str(exc)})
        except OSError as exc:
            self.send_json(500, {"error": str(exc)})


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", default="0.0.0.0")
    parser.add_argument("--port", type=int, default=8080)
    args = parser.parse_args()
    ThreadingHTTPServer((args.host, args.port), Handler).serve_forever()


if __name__ == "__main__":
    main()
