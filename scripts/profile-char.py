#!/usr/bin/env python3
"""Measure Char's CPU time (one-core percent), RSS, and an optional native stack sample."""
import argparse
import json
import subprocess
import time
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('pid', type=int)
parser.add_argument('--seconds', type=float, default=20)
parser.add_argument('--sample', type=Path, help='Save a 5-second macOS sample after measuring CPU')
args = parser.parse_args()

def snapshot():
    fields = subprocess.check_output(['ps', '-p', str(args.pid), '-o', 'time=,rss=,command='], text=True).strip().split(maxsplit=2)
    if len(fields) != 3 or '/Char.app/Contents/MacOS/Char' not in fields[2]:
        raise SystemExit('Choose the running Char app PID.')
    parts = [float(value) for value in fields[0].split(':')]
    cpu = sum(value * (60 ** index) for index, value in enumerate(reversed(parts)))
    return {'cpu_seconds': cpu, 'rss_kib': int(fields[1])}

start = snapshot()
began = time.monotonic()
time.sleep(args.seconds)
end = snapshot()
wall = time.monotonic() - began
print(json.dumps({'pid': args.pid, 'wall_seconds': wall,
                  'cpu_seconds': end['cpu_seconds'] - start['cpu_seconds'],
                  'single_core_percent': 100 * (end['cpu_seconds'] - start['cpu_seconds']) / wall,
                  'rss_start_kib': start['rss_kib'], 'rss_end_kib': end['rss_kib']}, indent=2), flush=True)
if args.sample:
    subprocess.run(['sample', str(args.pid), '5', '-file', str(args.sample)], check=True)
