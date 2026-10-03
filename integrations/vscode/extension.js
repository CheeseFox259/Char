'use strict';

const fs = require('node:fs');
const net = require('node:net');
const os = require('node:os');
const path = require('node:path');
const crypto = require('node:crypto');

function createController(vscode) {
  const anchors = new Map();

  function capture() {
    if (!vscode.window.state.focused) return { ok: false };
    const group = vscode.window.tabGroups.activeTabGroup;
    const tab = group?.activeTab;
    const editor = vscode.window.activeTextEditor;
    const terminal = vscode.window.activeTerminal;
    const editorCandidate = tab?.input instanceof vscode.TabInputText && editor &&
      editor.document.uri.toString() === tab.input.uri.toString() &&
      editor.viewColumn === group.viewColumn;
    const terminalCandidate = terminal && vscode.window.terminals.includes(terminal);
    // Public API retains both "most recently focused" references. Ambiguity is not an exact anchor.
    if (Boolean(editorCandidate) === Boolean(terminalCandidate)) return { ok: false };
    const token = crypto.randomUUID();
    anchors.set(token, editorCandidate ? { kind: 'editor', tab } : { kind: 'terminal', terminal });
    return { ok: true, token };
  }

  function contains(token) {
    const anchor = anchors.get(token);
    if (!anchor) return false;
    if (anchor.kind === 'terminal') return vscode.window.terminals.includes(anchor.terminal);
    return vscode.window.tabGroups.all.some(group => group.tabs.includes(anchor.tab));
  }

  function isActive(token) {
    const anchor = anchors.get(token);
    if (!anchor || !vscode.window.state.focused || !contains(token)) return false;
    if (anchor.kind === 'terminal') {
      return !vscode.window.activeTextEditor && vscode.window.activeTerminal === anchor.terminal;
    }
    return !vscode.window.activeTerminal && vscode.window.tabGroups.activeTabGroup?.activeTab === anchor.tab;
  }

  async function focus(token) {
    const anchor = anchors.get(token);
    if (!anchor || !contains(token)) return false;
    if (anchor.kind === 'terminal') {
      anchor.terminal.show(false);
      return isActive(token);
    }
    const group = vscode.window.tabGroups.all.find(group => group.tabs.includes(anchor.tab));
    if (!(anchor.tab.input instanceof vscode.TabInputText)) return false;
    await vscode.window.showTextDocument(anchor.tab.input.uri, {
      viewColumn: group.viewColumn, preserveFocus: false, preview: anchor.tab.isPreview
    });
    return isActive(token);
  }

  async function handle(request) {
    switch (request?.op) {
      case 'capture': return capture();
      case 'contains': return { ok: contains(request.token) };
      case 'isActive': return { ok: isActive(request.token) };
      case 'focus': return { ok: await focus(request.token) };
      default: return { ok: false };
    }
  }
  return { handle };
}

function activate(context) {
  const vscode = require('vscode');
  const controller = createController(vscode);
  const directory = path.join('/tmp', `char-vscode-${process.getuid()}`);
  try { fs.mkdirSync(directory, { mode: 0o700 }); }
  catch (error) { if (error.code !== 'EEXIST') throw error; }
  const stats = fs.lstatSync(directory);
  if (!stats.isDirectory() || stats.uid !== process.getuid() || (stats.mode & 0o077) !== 0) {
    throw new Error('Char bridge directory must be private and owned by this user');
  }
  const socketPath = path.join(directory, `bridge-${process.pid}-${crypto.randomUUID()}.sock`);
  const server = net.createServer(socket => {
    let input = '';
    socket.setTimeout(500);
    socket.on('data', data => {
      input += data.toString('utf8');
      if (input.length > 4096) { socket.destroy(); return; }
      const newline = input.indexOf('\n');
      if (newline < 0) return;
      let request;
      try { request = JSON.parse(input.slice(0, newline)); }
      catch { socket.end('{"ok":false}\n'); return; }
      Promise.resolve(controller.handle(request))
        .then(reply => socket.end(JSON.stringify(reply) + '\n'))
        .catch(() => socket.end('{"ok":false}\n'));
      input = '';
    });
  });
  server.listen(socketPath, () => fs.chmodSync(socketPath, 0o600));
  context.subscriptions.push({ dispose() {
    server.close();
    try { fs.unlinkSync(socketPath); } catch {}
  } });
}

module.exports = { activate, createController };
