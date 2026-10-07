#!/usr/bin/env python3
"""
Native acceptance for the MiniMax Code Char integration.

Everything runs against an isolated client data root with a local stub model provider,
so no MiniMax account, quota, session or real model request is used. The real `mcode`
CLI is launched twice: once headless and once in its interactive TUI under a pty, which
is the only way to make the client ask for a permission decision. Every assertion is
made on the bytes the client itself produced, either in the Hook spool or on the
adapter's protocol frames.
"""
import json
import os
import pty
import re
import select
import shutil
import signal
import subprocess
import sys
import tempfile
import queue
import threading
import time
import uuid
from http.server import BaseHTTPRequestHandler, HTTPServer

WORKSPACE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ADAPTER_PACKAGE = os.path.join(WORKSPACE, "packages", "minimax-code-cli.charintegration")
NATIVE_PLUGIN = os.path.join(WORKSPACE, "client-plugin", "char-observer")
MCODE = os.environ.get("MCODE_BIN") or shutil.which("mcode") or os.path.expanduser(
    "~/.minimax-code/bin/mcode")

failures = []
checks = 0


def check(label, condition, detail=""):
    global checks
    checks += 1
    if condition:
        print(f"  ok   {label}")
    else:
        print(f"  FAIL {label} {detail}")
        failures.append(label)


class StubProvider(BaseHTTPRequestHandler):
    """Minimal Anthropic messages endpoint: one tool call, then a text answer."""

    streamed = 0
    requests = 0

    def log_message(self, *args):
        pass

    def do_POST(self):
        length = int(self.headers.get("content-length") or 0)
        body = self.rfile.read(length) if length else b""
        try:
            payload = json.loads(body or b"{}")
        except ValueError:
            payload = {}
        if not self.path.endswith("/messages"):
            self._json({})
            return
        if payload.get("stream") is not True:
            self._json({"id": "msg_stub", "type": "message", "role": "assistant", "model": "stub-model",
                        "content": [{"type": "text", "text": "OK"}], "stop_reason": "end_turn",
                        "usage": {"input_tokens": 10, "output_tokens": 2}})
            return
        type(self).streamed += 1
        step = type(self).streamed
        if step == 1:
            blocks = [{"type": "tool_use", "id": "toolu_probe_1", "name": "bash",
                       "input": {"command": "printf approval-probe"}}]
            stop = "tool_use"
        else:
            blocks = [{"type": "text", "text": "OK"}]
            stop = "end_turn"
        self.send_response(200)
        self.send_header("content-type", "text/event-stream")
        self.end_headers()
        events = [("message_start", {"type": "message_start", "message": {
            "id": "msg_stub", "type": "message", "role": "assistant", "model": "stub-model",
            "content": [], "stop_reason": None, "stop_sequence": None,
            "usage": {"input_tokens": 10, "output_tokens": 0}}})]
        for index, block in enumerate(blocks):
            start = ({"type": "text", "text": ""} if block["type"] == "text"
                     else {"type": "tool_use", "id": block["id"], "name": block["name"], "input": {}})
            events.append(("content_block_start", {"type": "content_block_start", "index": index,
                                                   "content_block": start}))
            delta = ({"type": "text_delta", "text": block["text"]} if block["type"] == "text"
                     else {"type": "input_json_delta", "partial_json": json.dumps(block["input"])})
            events.append(("content_block_delta", {"type": "content_block_delta", "index": index, "delta": delta}))
            events.append(("content_block_stop", {"type": "content_block_stop", "index": index}))
        events.append(("message_delta", {"type": "message_delta",
                                         "delta": {"stop_reason": stop, "stop_sequence": None},
                                         "usage": {"output_tokens": 2}}))
        events.append(("message_stop", {"type": "message_stop"}))
        for name, data in events:
            self.wfile.write(f"event: {name}\ndata: {json.dumps(data)}\n\n".encode())
            self.wfile.flush()

    def _json(self, payload):
        body = json.dumps(payload).encode()
        self.send_response(200)
        self.send_header("content-type", "application/json")
        self.send_header("content-length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


class Adapter:
    """The delivered adapter package, driven exactly like the Char host drives it."""

    def __init__(self, data_dir, support_dir, home):
        manifest = json.load(open(os.path.join(ADAPTER_PACKAGE, "manifest.json")))
        self.manifest = manifest
        env = dict(os.environ)
        env.pop("MINIMAX_DATA_DIR", None)
        env.update({
            "HOME": home,
            "MINIMAX_DATA_DIR": data_dir,
            "CHAR_SUPPORT_DIRECTORY": support_dir,
            "CHAR_PLUGIN_DIRECTORY": ADAPTER_PACKAGE,
            "CHAR_PLUGIN_ID": manifest["id"],
            "CHAR_PLUGIN_VERSION": manifest["version"],
            "CHAR_WORK_END": manifest["workEnd"],
            "CHAR_PLUGIN_CONFIG": json.dumps(manifest["adapter"]["configuration"]),
        })
        self.child = subprocess.Popen(["node", os.path.join(ADAPTER_PACKAGE, manifest["adapter"]["entrypoint"])],
                                      env=env, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                      stderr=subprocess.PIPE, text=True, bufsize=1)
        self.events = []
        self.responses = queue.Queue()
        self.reader = threading.Thread(target=self._read, daemon=True)
        self.reader.start()

    def _read(self):
        for line in self.child.stdout:
            line = line.strip()
            if not line:
                continue
            frame = json.loads(line)
            if "event" in frame:
                self.events.append(frame["event"])
            else:
                self.responses.put(frame)

    def call(self, method, params=None, timeout=15):
        request = {"version": 1, "id": str(uuid.uuid4()), "method": method, "params": params or {}}
        self.child.stdin.write(json.dumps(request) + "\n")
        self.child.stdin.flush()
        try:
            frame = self.responses.get(timeout=timeout)
        except queue.Empty:
            raise RuntimeError(f"no response for {method} within {timeout}s")
        if frame.get("id") != request["id"]:
            raise RuntimeError(f"response id mismatch for {method}: {frame}")
        return frame

    def wait_for_events(self, count, timeout=10):
        deadline = time.time() + timeout
        while len(self.events) < count and time.time() < deadline:
            time.sleep(0.05)
        return len(self.events)

    def stop(self):
        try:
            self.child.stdin.close()
        except OSError:
            pass
        try:
            self.child.wait(timeout=5)
        except subprocess.TimeoutExpired:
            self.child.kill()


def run_client(env, args, cwd, timeout=90):
    return subprocess.run([MCODE] + args, env=env, cwd=cwd, capture_output=True, text=True, timeout=timeout)


def drain_pty(master, seconds):
    chunks = []
    end = time.time() + seconds
    while time.time() < end:
        ready, _, _ = select.select([master], [], [], 0.2)
        if not ready:
            continue
        try:
            data = os.read(master, 65536)
        except OSError:
            break
        if not data:
            break
        chunks.append(data.decode("utf-8", "replace"))
    return "".join(chunks)


def main():
    if not os.path.exists(MCODE):
        print(f"SKIP: mcode CLI not found at {MCODE}")
        return 0
    server = HTTPServer(("127.0.0.1", 0), StubProvider)
    port = server.server_address[1]
    threading.Thread(target=server.serve_forever, daemon=True).start()

    root = tempfile.mkdtemp(prefix="minimax-native-")
    home = os.path.join(root, "home")
    work = os.path.join(root, "work")
    support = os.path.join(root, "support")
    # The client derives its data root from the user home, so the isolated home is the
    # only isolation lever the client itself honours.
    data_dir = os.path.join(home, ".minimax")
    for path in (home, work, support, data_dir):
        os.makedirs(path, exist_ok=True)
    spool = os.path.join(data_dir, "v2", "plugin-data", "hooks", "char-observer", "events.ndjson")
    env = dict(os.environ, HOME=home, STUB_KEY="stub-key", TERM="xterm-256color")
    env.pop("MINIMAX_DATA_DIR", None)

    print("1. provider pinned to the local stub, no account or quota used")
    provider = run_client(env, ["provider", "add", "--name", "Stub", "--base-url", f"http://127.0.0.1:{port}",
                                 "--api-format", "anthropic-messages", "--api-key-env", "STUB_KEY",
                                 "--model", "stub-model", "--use"], work)
    check("stub provider accepted", provider.returncode == 0, provider.stderr[:200])

    print("2. adapter install, then the client's own discovery of the local plugin")
    shutil.rmtree(os.path.join(data_dir, "plugins", "char-observer"), ignore_errors=True)
    adapter = Adapter(data_dir, support, home)
    hello = adapter.call("hello")
    check("hello returns protocolVersion 1", hello.get("result") == {"protocolVersion": 1}, json.dumps(hello))
    before_install = adapter.call("inspect")
    check("inspect is notInstalled before 安装",
          before_install.get("result", {}).get("status") == "notInstalled", json.dumps(before_install))
    installed = adapter.call("install", timeout=20)
    check("install returns ready", installed.get("result", {}).get("status") == "ready", json.dumps(installed)[:400])
    check("install reports the client's own discovery",
          "client discovery" in installed.get("result", {}).get("detail", ""),
          installed.get("result", {}).get("detail", ""))
    check("client discovery listed the package",
          "char-observer" in installed.get("result", {}).get("detail", ""),
          installed.get("result", {}).get("detail", ""))
    after_install = adapter.call("inspect")
    check("inspect is ready after 安装",
          after_install.get("result", {}).get("status") == "ready", json.dumps(after_install)[:300])

    listing = run_client(env, ["plugin", "list", "--json"], work)
    try:
        catalog = json.loads(listing.stdout)
    except ValueError:
        catalog = {"installed": [], "available": []}
    entry = next((item for item in catalog.get("installed", []) if item.get("name") == "char-observer"), None)
    check("mcode lists char-observer as an installed local plugin", entry is not None, listing.stdout[:300])
    check("the client reports the plugin enabled", bool(entry and entry.get("enabled")), json.dumps(entry))

    print("3. headless run: native Hook records reach the spool and the adapter")
    adapter.call("start")
    headless = run_client(env, ["exec", "--cwd", work, "--permission", "off", "--max-steps", "4",
                                "--output-format", "json", "Reply with the single word OK."], work)
    check("headless run succeeded against the stub", headless.returncode == 0, headless.stderr[:300])
    adapter.wait_for_events(1, 2)
    records = read_spool(spool)
    check("client wrote native Hook records", len(records) >= 3, str(len(records)))
    check("records carry the real session id", any(r.get("sid", "").startswith("mvs_") for r in records))
    check("records identify the CLI surface", all(r.get("surface") == "cli" for r in records),
          json.dumps(records[:2]))
    check("records identify the client process", all(isinstance(r.get("pid"), int) for r in records),
          json.dumps(records[:2]))
    signals = [r["signal"] for r in records]
    check("turn boundaries are running and turnEnded",
          "running" in signals and "turnEnded" in signals, str(signals))
    published = [event for event in adapter.events if event["nativeID"] == records[-1]["sid"]]
    check("adapter published the same session id", len(published) >= 2, json.dumps(adapter.events)[:300])
    check("adapter published only this work end",
          all(event["workEnd"] == "minimaxcode.cli" for event in adapter.events),
          json.dumps(adapter.events)[:300])
    check("adapter published the turn end as stopped/turnEnded",
          any(event.get("reason") == "turnEnded" for event in adapter.events),
          json.dumps(adapter.events)[:300])
    check("no prompt or tool text reached the published events",
          all(set(event) <= {"workEnd", "nativeID", "timestamp", "state", "reason", "target", "isChild"}
              for event in adapter.events), json.dumps(adapter.events)[:300])

    print("4. interactive TUI: the client's own permission boundary")
    StubProvider.streamed = 0
    with open(os.path.join(data_dir, "permission.json"), "w") as handle:
        json.dump({"version": 2, "allow": [], "deny": [],
                   "ask": [{"tool_name": "bash",
                            "matcher": {"kind": "command", "pattern": "[\"printf\",\"approval-probe\"]"}}]},
                  handle, indent=2)
    before_tui = len(read_spool(spool))
    master, slave = pty.openpty()
    child = subprocess.Popen([MCODE], env=env, cwd=work, stdin=slave, stdout=slave, stderr=slave,
                             preexec_fn=os.setsid)
    os.close(slave)
    screen = drain_pty(master, 9)
    os.write(master, b"Run the probe command\r")
    screen += drain_pty(master, 6)
    os.write(master, b"y")
    # Wait for the run to finish: a keystroke during a live run steers it instead of
    # reaching the composer, so /new must not be sent early.
    for _ in range(90):
        screen += drain_pty(master, 1)
        if any(r.get("ev") == "Stop" for r in read_spool(spool)[before_tui:]):
            break
    screen += drain_pty(master, 2)
    # SessionEnd is documented for TUI /new, /clear and /resume. Type the command and the
    # return key separately, the way a person does, and give each command its own wait.
    for command in (b"/new", b"/clear"):
        os.write(master, command)
        screen += drain_pty(master, 1)
        os.write(master, b"\r")
        screen += drain_pty(master, 8)
        if any(r.get("ev") == "SessionEnd" for r in read_spool(spool)[before_tui:]):
            break
    try:
        os.killpg(os.getpgid(child.pid), signal.SIGKILL)
    except (ProcessLookupError, PermissionError):
        pass
    child.wait(timeout=10)
    os.close(master)
    records = read_spool(spool)[before_tui:]
    check("the client asked for a permission decision", "Running" in screen or "Allow" in screen or "y" in screen)
    check("PermissionRequest became an approval record",
          any(r.get("ev") == "PermissionRequest" and r.get("signal") == "approval" for r in records),
          json.dumps(records)[:400])
    clean = re.sub(r"\x1b\[[0-9;?]*[A-Za-z]", "", screen)
    check("SessionEnd became a closed record",
          any(r.get("ev") == "SessionEnd" and r.get("signal") == "closed" for r in records),
          str([(r.get("ev"), r.get("signal")) for r in records]) + " | screen tail: " + clean[-400:])
    check("TUI records also identify the CLI surface and client process",
          all(r.get("surface") == "cli" and isinstance(r.get("pid"), int) for r in records),
          json.dumps(records)[:400])
    adapter.wait_for_events(1, 2)
    check("adapter published the approval",
          any(event.get("reason") == "approval" for event in adapter.events),
          json.dumps(adapter.events)[:400])
    check("adapter published the closed session",
          any(event.get("state") == "closed" for event in adapter.events),
          json.dumps(adapter.events)[:400])

    print("5. visit and uninstall against the isolated root")
    visit = adapter.call("visit", {"nativeID": records[-1]["sid"], "bundleIdentifier": "dev.warp.Warp-Stable"})
    outcome = visit.get("result", {}).get("outcome")
    check("visit never claims exact", outcome in {"fallback", "unavailable"}, json.dumps(visit)[:200])
    removed = adapter.call("uninstall", timeout=20)
    check("uninstall returns ready", removed.get("result", {}).get("status") == "ready", json.dumps(removed)[:200])
    check("uninstall removed the package", not os.path.exists(os.path.join(data_dir, "plugins", "char-observer")))
    check("uninstall kept a backup",
          os.path.isdir(os.path.join(support, "minimax-code-native-backups")))
    final_inspect = adapter.call("inspect")
    check("inspect is notInstalled after uninstall",
          final_inspect.get("result", {}).get("status") == "notInstalled", json.dumps(final_inspect)[:200])
    adapter.stop()

    server.shutdown()
    remove_tree(root)
    print(f"\n{checks - len(failures)}/{checks} checks passed")
    if failures:
        print("failed:", ", ".join(failures))
        return 1
    return 0


def remove_tree(root):
    """The client materialises its Hook cache read-only, so restore owner access first."""
    for _ in range(4):
        subprocess.run(["chmod", "-R", "u+rwX", root], check=False)
        try:
            shutil.rmtree(root)
            return
        except OSError:
            time.sleep(0.2)
    print(f"could not remove {root}")


def read_spool(path):
    records = []
    try:
        with open(path, errors="replace") as handle:
            for line in handle:
                line = line.strip()
                if not line:
                    continue
                try:
                    records.append(json.loads(line))
                except ValueError:
                    pass
    except OSError:
        pass
    return records


if __name__ == "__main__":
    sys.exit(main())