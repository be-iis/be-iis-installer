#!/usr/bin/env python3
"""Small local control page for the BE-IIS HPP SPE Noise Generator."""

from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import argparse
import json
import subprocess
import urllib.parse

I2C_BUS = 1
I2C_ADDRESS = 0x42
REG_CTRL = 0x01
REG_RATE_DIVIDER = 0x02


def write_register(register: int, value: int) -> None:
    """Write one 8-bit register through the Linux i2c-tools utility."""
    subprocess.run(
        ["i2cset", "-y", str(I2C_BUS), hex(I2C_ADDRESS), hex(register), hex(value), "b"],
        check=True, capture_output=True, text=True,
    )


PAGE = """<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>BE-IIS Noise Generator</title><style>
body{font-family:system-ui,sans-serif;max-width:620px;margin:3rem auto;padding:0 1.2rem;color:#182431}
h1{margin-bottom:.2rem}.card{border:1px solid #d8dee5;border-radius:10px;padding:1.4rem;margin-top:1.5rem}
button{border:0;border-radius:6px;padding:.7rem 1rem;font-size:1rem;cursor:pointer;color:#fff;background:#1265a8}
button.off{background:#5b6570}input[type=range]{width:100%}.row{display:flex;gap:.75rem;align-items:center;flex-wrap:wrap}
#status{min-height:1.4rem;margin-top:1rem;color:#425466}footer{margin-top:2rem;font-size:.9rem}a{color:#1265a8}
</style></head><body>
<h1>Noise Generator</h1><p>BE-IIS HPP SPE Noise Generator local control</p>
<div class="card"><h2>Output</h2><div class="row">
<button onclick="setEnabled(true)">Enable output</button><button class="off" onclick="setEnabled(false)">Disable output</button>
</div><p>The output is enabled by default after power-on.</p></div>
<div class="card"><h2>Update rate</h2><label for="divider">Rate divider: <strong id="value">9</strong></label>
<input id="divider" type="range" min="0" max="255" value="9" oninput="value.textContent=this.value">
<div class="row"><button onclick="setRate()">Apply rate</button></div>
<p>0 updates on every oscillator cycle. Higher values slow the noise update rate.</p></div>
<p id="status"></p><footer><a href="https://www.be-iis.eu/" target="_blank" rel="noopener">www.be-iis.eu</a></footer>
<script>
async function command(data){const r=await fetch('/api/control',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(data)});const j=await r.json();if(!r.ok)throw Error(j.error);status.textContent=j.message;}
async function setEnabled(enabled){try{await command({enabled})}catch(e){status.textContent='Error: '+e.message}}
async function setRate(){try{await command({divider:Number(divider.value)})}catch(e){status.textContent='Error: '+e.message}}
</script></body></html>"""


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        print("%s - %s" % (self.address_string(), fmt % args))

    def reply_json(self, status: int, payload: dict) -> None:
        data = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        if self.path != "/":
            self.send_error(404)
            return
        data = PAGE.encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_POST(self):
        if self.path != "/api/control":
            self.send_error(404)
            return
        try:
            length = int(self.headers.get("Content-Length", "0"))
            payload = json.loads(self.rfile.read(length))
            if "enabled" in payload:
                write_register(REG_CTRL, 1 if payload["enabled"] else 0)
                message = "Output enabled." if payload["enabled"] else "Output disabled."
            elif "divider" in payload and isinstance(payload["divider"], int) and 0 <= payload["divider"] <= 255:
                write_register(REG_RATE_DIVIDER, payload["divider"])
                message = f"Rate divider set to {payload['divider']}."
            else:
                raise ValueError("Invalid control value")
            self.reply_json(200, {"message": message})
        except (ValueError, json.JSONDecodeError) as exc:
            self.reply_json(400, {"error": str(exc)})
        except subprocess.CalledProcessError as exc:
            self.reply_json(500, {"error": f"I2C write failed: {exc.stderr.strip()}"})


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", default="127.0.0.1", help="bind address (default: localhost only)")
    parser.add_argument("--port", type=int, default=8080, help="TCP port (default: 8080)")
    args = parser.parse_args()
    print(f"Noise Generator webtool: http://{args.host}:{args.port}")
    ThreadingHTTPServer((args.host, args.port), Handler).serve_forever()


if __name__ == "__main__":
    main()
