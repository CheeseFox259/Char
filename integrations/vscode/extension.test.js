'use strict';

const assert = require('node:assert/strict');
const test = require('node:test');
const { createController } = require('./extension');

class TabInputText { constructor(uri) { this.uri = uri; } }
const uri = text => ({ toString: () => text });

function fixture() {
  const first = { input: new TabInputText(uri('file:///fixture/first')), isPreview: false };
  const second = { input: new TabInputText(uri('file:///fixture/second')), isPreview: false };
  const group = { viewColumn: 1, tabs: [first, second], activeTab: first };
  const window = {
    state: { focused: true },
    tabGroups: { all: [group], activeTabGroup: group },
    activeTextEditor: { document: { uri: first.input.uri }, viewColumn: 1 },
    activeTerminal: undefined,
    terminals: [],
    showTextDocument: async () => { group.activeTab = first; }
  };
  return { first, second, group, window, vscode: { window, TabInputText } };
}

test('captures and returns to the same existing editor tab', async () => {
  const { group, second, vscode } = fixture();
  const controller = createController(vscode);
  const captured = await controller.handle({ op: 'capture' });
  assert.equal(captured.ok, true);
  group.activeTab = second;
  assert.equal((await controller.handle({ op: 'focus', token: captured.token })).ok, true);
  assert.equal((await controller.handle({ op: 'isActive', token: captured.token })).ok, true);
});

test('closed tab is refused without reopening', async () => {
  const { first, group, vscode } = fixture();
  const controller = createController(vscode);
  const captured = await controller.handle({ op: 'capture' });
  group.tabs = group.tabs.filter(tab => tab !== first);
  vscode.window.showTextDocument = () => { throw new Error('must not reopen'); };
  assert.equal((await controller.handle({ op: 'contains', token: captured.token })).ok, false);
  assert.equal((await controller.handle({ op: 'focus', token: captured.token })).ok, false);
});

test('ambiguous editor and terminal state gives no anchor', async () => {
  const { vscode } = fixture();
  const terminal = { show() {} };
  vscode.window.activeTerminal = terminal;
  vscode.window.terminals = [terminal];
  assert.equal((await createController(vscode).handle({ op: 'capture' })).ok, false);
});

test('a sole terminal can be captured and selected', async () => {
  const { vscode } = fixture();
  vscode.window.activeTextEditor = undefined;
  const terminal = { show() { vscode.window.activeTerminal = terminal; } };
  vscode.window.activeTerminal = terminal;
  vscode.window.terminals = [terminal];
  const controller = createController(vscode);
  const captured = await controller.handle({ op: 'capture' });
  assert.equal(captured.ok, true);
  vscode.window.activeTerminal = undefined;
  assert.equal((await controller.handle({ op: 'focus', token: captured.token })).ok, true);
  vscode.window.activeTextEditor = { document: { uri: uri('file:///fixture/new') }, viewColumn: 1 };
  assert.equal((await controller.handle({ op: 'isActive', token: captured.token })).ok, false);
});
