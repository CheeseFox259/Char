// Observation spool tailing with an explicit EOF baseline.
// The native Hook appends one JSON object per line from every MiniMax Code process.
import {closeSync, existsSync, fstatSync, openSync, readSync, statSync, watch} from 'node:fs';
import {dirname as dirnameOf} from 'node:path';

const MAX_READ_BYTES = 512 * 1024;
const MAX_LINE_BYTES = 1024 * 1024;

function readRange(path, offset, length) {
  const descriptor = openSync(path, 'r');
  try {
    const buffer = Buffer.allocUnsafe(length);
    const read = readSync(descriptor, buffer, 0, length, offset);
    return buffer.subarray(0, read).toString('utf8');
  } finally {
    closeSync(descriptor);
  }
}

/**
 * Tail an append-only file. Reading starts at the current EOF so a start never
 * replays history, half-written lines are never published, rotation is detected by
 * inode change, truncation starts a new observation generation, and a file that does
 * not exist yet starts one when its directory appears.
 */
export class SpoolTail {
  constructor(path, {onRecord, onRotate} = {}) {
    this.path = path;
    this.onRecord = onRecord ?? (() => {});
    this.onRotate = onRotate ?? (() => {});
    this.offset = 0;
    this.identity = null;
    this.buffer = '';
    this.watcher = null;
    this.directoryWatcher = null;
    this.draining = false;
    this.stopped = false;
  }

  /** Open the file and start from its current end. Never reads pre-existing lines. */
  start(directory) {
    this.targetDirectory = directory ?? dirnameOf(this.path);
    this.baseline();
    this.arm();
    this.schedule();
  }

  /**
   * Watch the spool file when it exists and always watch its directory, so a rotation
   * (rename plus create) still delivers an event. When the directory does not exist yet
   * the nearest existing ancestor is watched and the watch is re-armed on any event.
   */
  arm() {
    this.watchFile();
    this.watchNearestExistingDirectory();
  }

  watchFile() {
    if (this.watcher) return;
    try {
      this.watcher = watch(this.path, () => this.schedule(), {persistent: false});
    } catch {
      this.watcher = null;
    }
  }

  watchNearestExistingDirectory() {
    let candidate = this.targetDirectory;
    while (candidate && !existsSync(candidate)) {
      const parent = dirnameOf(candidate);
      if (parent === candidate) break;
      candidate = parent;
    }
    if (!candidate) return;
    try {
      this.directoryWatcher?.close();
      this.directoryWatcher = watch(candidate, () => {
        this.arm();
        this.schedule();
      }, {persistent: false});
    } catch {
      this.directoryWatcher = null;
    }
  }

  /** Record the current end-of-file without publishing anything. */
  baseline() {
    try {
      const descriptor = openSync(this.path, 'r');
      const stats = fstatSync(descriptor);
      closeSync(descriptor);
      this.identity = `${stats.dev}:${stats.ino}`;
      this.offset = stats.size;
    } catch {
      this.identity = null;
      this.offset = 0;
    }
    this.buffer = '';
  }

  schedule() {
    if (this.draining || this.stopped) return;
    this.draining = true;
    setImmediate(() => {
      this.draining = false;
      if (this.stopped) return;
      try {
        this.drain();
      } catch {
        /* A transient read failure must not end the subscription. */
      }
      // A burst larger than one window keeps draining without new input.
      if (!this.stopped && this.pendingBytes() > 0) this.schedule();
    });
  }

  pendingBytes() {
    try {
      return Math.max(0, statSync(this.path).size - this.offset);
    } catch {
      return 0;
    }
  }

  drain() {
    let stats;
    try {
      stats = statSync(this.path);
    } catch {
      this.arm();
      return;
    }
    const identity = `${stats.dev}:${stats.ino}`;
    if (this.identity !== null && identity !== this.identity) {
      this.identity = identity;
      this.offset = 0;
      this.buffer = '';
      this.onRotate();
    }
    this.identity = identity;
    if (stats.size === this.offset) return;
    if (stats.size < this.offset) {
      this.offset = 0;
      this.buffer = '';
    }
    const length = Math.min(stats.size - this.offset, MAX_READ_BYTES);
    if (length <= 0) return;
    let chunk;
    try {
      chunk = readRange(this.path, this.offset, length);
    } catch {
      return;
    }
    this.offset += Buffer.byteLength(chunk, 'utf8');
    this.buffer += chunk;
    let index = this.buffer.indexOf('\n');
    while (index >= 0) {
      const line = this.buffer.slice(0, index);
      this.buffer = this.buffer.slice(index + 1);
      if (line.trim()) this.onRecord(line);
      index = this.buffer.indexOf('\n');
    }
    // Never let an unterminated line grow without bound.
    if (Buffer.byteLength(this.buffer, 'utf8') > MAX_LINE_BYTES) this.buffer = '';
  }

  stop() {
    this.stopped = true;
    try {
      this.watcher?.close();
    } catch {
      /* already closed */
    }
    try {
      this.directoryWatcher?.close();
    } catch {
      /* already closed */
    }
    this.watcher = null;
    this.directoryWatcher = null;
  }
}