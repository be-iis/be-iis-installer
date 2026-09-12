#!/usr/bin/env python3
"""Local web control for the BE-IIS HPP SPE Noise Generator."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import argparse
import json

SYSFS = Path("/sys/bus/i2c/devices/1-002a")
BOOLS = {"output_enable", "dds_enable", "fm_enable"}
STATUS = ("component_id", "firmware_id", "generator", "output_enable",
          "amplitude", "pwm_reference", "dds_enable", "fm_enable")


def state():
    return {name: (SYSFS / name).read_text().strip() for name in STATUS}


def write(values):
    for name, value in values.items():
        if name == "generator" and value not in ("null", "prn", "dds"):
            raise ValueError("Invalid generator")
        if name in BOOLS:
            value = str(value)
            if value not in ("0", "1"):
                raise ValueError("Invalid boolean value")
        elif name == "amplitude":
            if not isinstance(value, int) or not 0 <= value <= 255:
                raise ValueError("Amplitude must be 0..255")
            value = str(value)
        elif name == "pwm_reference":
            if not isinstance(value, int) or not 0 <= value <= 1023:
                raise ValueError("PWM reference must be 0..1023")
            value = str(value)
        elif name != "generator":
            raise ValueError(f"Unsupported setting: {name}")
        (SYSFS / name).write_text(str(value) + "\n")


PAGE = """<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>BE-IIS Noise Generator</title><style>body{font-family:system-ui,sans-serif;max-width:680px;margin:2.5rem auto;padding:0 1.2rem;color:#182431}h1{margin-bottom:.2rem}.card{border:1px solid #d8dee5;border-radius:10px;padding:1.25rem;margin-top:1rem}label{display:block;margin:.65rem 0 .25rem}button{border:0;border-radius:6px;padding:.7rem 1rem;font-size:1rem;cursor:pointer;color:#fff;background:#1265a8}input[type=range]{width:100%}select,input[type=number]{font:inherit;padding:.35rem;width:100%;box-sizing:border-box}.check{display:flex;gap:.5rem;align-items:center}.check input{width:auto}#status{min-height:1.4rem;margin-top:1rem;color:#425466}footer{margin-top:2rem;font-size:.9rem}a{color:#1265a8}</style></head><body>
<h1>Noise Generator</h1><p>BE-IIS HPP SPE Noise Generator</p>
<div class="card"><label>Generator<select id="generator"><option value="null">Off (null)</option><option value="prn">PRN noise</option><option value="dds">DDS</option></select></label><label class="check"><input id="output_enable" type="checkbox">Enable output</label><label>Amplitude: <strong id="amplitude_value">0</strong><input id="amplitude" type="range" min="0" max="255" oninput="amplitude_value.textContent=this.value"></label><button onclick="main()">Apply output settings</button></div>
<div class="card"><h2>DDS / FM</h2><label class="check"><input id="dds_enable" type="checkbox">Enable DDS</label><label class="check"><input id="fm_enable" type="checkbox">Enable FM</label><label>PWM reference<input id="pwm_reference" type="number" min="0" max="1023"></label><button onclick="dds()">Apply DDS settings</button></div><p id="status"></p><footer><span id="identity"></span> · <a href="https://www.be-iis.eu/" target="_blank" rel="noopener">www.be-iis.eu</a></footer>
<script>async function req(path,data){const r=await fetch(path,{method:data?'POST':'GET',headers:{'Content-Type':'application/json'},body:data?JSON.stringify(data):undefined});const j=await r.json();if(!r.ok)throw Error(j.error);return j}function display(s){generator.value=s.generator;output_enable.checked=s.output_enable==='1';amplitude.value=s.amplitude;amplitude_value.textContent=s.amplitude;dds_enable.checked=s.dds_enable==='1';fm_enable.checked=s.fm_enable==='1';pwm_reference.value=s.pwm_reference;identity.textContent='Component '+s.component_id+', firmware '+s.firmware_id}async function apply(v){try{display((await req('/api/settings',v)).status);status.textContent='Settings applied.'}catch(e){status.textContent='Error: '+e.message}}function main(){apply({generator:generator.value,output_enable:output_enable.checked?'1':'0',amplitude:Number(amplitude.value)})}function dds(){apply({dds_enable:dds_enable.checked?'1':'0',fm_enable:fm_enable.checked?'1':'0',pwm_reference:Number(pwm_reference.value)})}req('/api/status').then(display).catch(e=>status.textContent='Error: '+e.message)</script></body></html>"""


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        print("%s - %s" % (self.address_string(), fmt % args))

    def send_json(self, code, result):
        data = json.dumps(result).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        try:
            if self.path == "/":
                data = PAGE.encode()
                self.send_response(200); self.send_header("Content-Type", "text/html; charset=utf-8"); self.send_header("Content-Length", str(len(data))); self.end_headers(); self.wfile.write(data)
            elif self.path == "/api/status":
                self.send_json(200, state())
            else:
                self.send_error(404)
        except OSError as exc:
            self.send_json(500, {"error": str(exc)})

    def do_POST(self):
        if self.path != "/api/settings":
            self.send_error(404); return
        try:
            values = json.loads(self.rfile.read(int(self.headers.get("Content-Length", "0"))))
            if not isinstance(values, dict):
                raise ValueError("Settings must be an object")
            write(values)
            self.send_json(200, {"status": state()})
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
