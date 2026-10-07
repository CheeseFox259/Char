#!/usr/bin/env node
/**
 * Performance samples for the MiniMax Code integration.
 * Reports raw numbers with their conditions instead of a single headline figure:
 * the client Hook process cost, the adapter's steady idle cost, and the
 * append → published-event latency of the observation path.
 */
import {execFileSync} from 'node:child_process';
import {appendFileSync, mkdirSync, readFileSync, rmSync} from 'node:fs';
import {dirname, join} from 'node:path';
import {AdapterProcess, cliPackage, hookRecord, isolatedEnvironment, sleep, spoolDirectory, workspace} from './harness.mjs';

const packageRoot = workspace;
const emitScript = join(packageRoot, 'client-plugin', 'char-observer', 'hooks', 'emit.mjs');

async function hookCost(environment) {
  const payload = JSON.stringify({
    hook_event_name: 'Stop', session_id: 'mvs_perf', cwd: '/private/tmp/perf',
    transcript_path: '/private/tmp/perf/transcript.jsonl', stop_hook_active: false,
  });
  const run = () => {
    const started = process.hrtime.bigint();
    try {
      execFileSync('node', [emitScript], {
        env: {...process.env, PLUGIN_DATA: spoolDirectory(environment)},
        input: payload,
        timeout: 10000,
        stdio: ['pipe', 'ignore', 'ignore'],
      });
      return {ms: Number(process.hrtime.bigint() - started) / 1e6, error: null};
    } catch (error) {
      return {ms: Number(process.hrtime.bigint() - started) / 1e6, error};
    }
  };
  for (let index = 0; index < 3; index += 1) await run();
  const samples = [];
  for (let index = 0; index < 15; index += 1) samples.push(await run());
  const durations = samples.map((sample) => sample.ms).sort((a, b) => a - b);
  const failed = samples.filter((sample) => sample.error);
  return {
    label: 'client Hook process (node cold start → append)',
    unit: 'ms per event, wall clock',
    warmup: 3,
    samples: durations.map((value) => Number(value.toFixed(1))),
    median: Number(durations[Math.floor(durations.length / 2)].toFixed(1)),
    max: Number(durations.at(-1).toFixed(1)),
    failures: failed.length,
    firstError: failed[0] ? String(failed[0].error?.message ?? failed[0].error) : null,
  };
}

function sampleProcess(pid) {
  const output = execFileSync('/bin/ps', ['-o', 'rss=,time=', '-p', String(pid)], {encoding: 'utf8'}).trim();
  if (!output) return null;
  const [rss, time] = output.split(/\s+/);
  const [minutes, seconds] = time.split(':');
  return {rssKB: Number(rss), cpuSeconds: Number(Number(minutes) * 60 + Number(seconds))};
}

async function idleCost(environment) {
  const adapter = new AdapterProcess(cliPackage, environment);
  await adapter.call('start');
  await sleep(1000);
  const first = sampleProcess(adapter.child.pid);
  const rss = [];
  const cpu = [];
  for (let second = 0; second < 20; second += 1) {
    await sleep(1000);
    const sample = sampleProcess(adapter.child.pid);
    if (!sample) break;
    rss.push(sample.rssKB);
    cpu.push(sample.cpuSeconds);
  }
  const last = sampleProcess(adapter.child.pid);
  await adapter.stop();
  return {
    label: 'adapter process, monitor started, spool quiet',
    unit: 'RSS in KiB, ps CPU as cumulative seconds since process start',
    warmupSeconds: 1,
    samplingSeconds: 20,
    rss: {first: first?.rssKB, last: last?.rssKB, min: Math.min(...rss), max: Math.max(...rss)},
    cpu: {first: first?.cpuSeconds, last: last?.cpuSeconds, deltaSeconds: last && first ? Number((last.cpuSeconds - first.cpuSeconds).toFixed(2)) : null},
  };
}

async function appendLatency(environment) {
  const adapter = new AdapterProcess(cliPackage, environment);
  await adapter.call('start');
  const total = 200;
  const sent = [];
  for (let index = 0; index < total; index += 1) {
    sent.push(Date.now());
    appendFileSync(environment.spool, `${JSON.stringify(hookRecord({sid: 'mvs_latency'}))}\n`);
  }
  const started = Date.now();
  await adapter.waitForEvents(total, 15000);
  const finished = Date.now();
  await adapter.stop();
  return {
    label: 'spool append → adapter event frame (same machine, no Char UI)',
    unit: 'ms for the whole burst of 200 records',
    records: total,
    burstDurationMs: finished - started,
    firstEventAfterMs: finished - sent[0],
    published: adapter.events.length,
  };
}

const environment = isolatedEnvironment('minimax-perf');
mkdirSync(spoolDirectory(environment), {recursive: true});
const results = [await hookCost(environment), await idleCost(environment), await appendLatency(environment)];
console.log(JSON.stringify({conditions: {node: process.version, host: 'macOS', packages: [cliPackage]}, results}, null, 2));
environment.cleanup();