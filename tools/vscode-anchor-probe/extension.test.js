'use strict';

const assert = require('node:assert/strict');
const test = require('node:test');
const { createController } = require('./extension');

class TabInputText { constructor(uri) { this.uri = uri; } }
const uri = value => ({ toString: () => value });

function editorFixture() {
  const tab = { input: new TabInputText(uri('file:///fixture/a.txt')), isPreview: false };
  const other = { input: new TabInputText(uri('file:///fixture/b.txt')), isPreview: false };
  const group = { viewColumn: 1, tabs: [tab, other], activeTab: tab };
  const window = {
    tabGroups: { all: [group], activeTabGroup: group },
    activeTextEditor: { document: { uri: tab.input.uri }, viewColumn: 1 },
    showTextDocument: async (_uri, options) => {
      assert.equal(options.viewColumn, 1);
      group.activeTab = tab;
    }
  };
  return { tab, other, group, window, vscode: { window, TabInputText } };
}

test('selects the same still-open editor tab', async () => {
  const { group, other, vscode } = editorFixture();
  const controller = createController(vscode);
  assert.equal(controller.captureEditor(), 'Captured the current editor tab');
  group.activeTab = other;
  assert.equal(await controller.returnToAnchor(), 'Exact editor tab selected');
});

test('does not recreate a closed editor tab', async () => {
  const { group, tab, vscode } = editorFixture();
  const controller = createController(vscode);
  controller.captureEditor();
  group.tabs = group.tabs.filter(candidate => candidate !== tab);
  vscode.window.showTextDocument = () => { throw new Error('must not open document'); };
  assert.equal(await controller.returnToAnchor(), 'Original editor tab is closed or identity changed');
});

test('does not report exact editor focus when VS Code selects another tab', async () => {
  const { group, other, vscode } = editorFixture();
  const controller = createController(vscode);
  controller.captureEditor();
  group.activeTab = other;
  vscode.window.showTextDocument = async () => {};
  assert.equal(await controller.returnToAnchor(), 'Editor focus unverified');
});

test('selects the same live terminal object, and rejects a closed one', async () => {
  const terminal = { show: () => { vscode.window.activeTerminal = terminal; } };
  const vscode = { window: { activeTerminal: terminal, terminals: [terminal] } };
  const controller = createController(vscode);
  assert.equal(controller.captureTerminal(), 'Captured the current terminal');
  vscode.window.activeTerminal = undefined;
  assert.equal(await controller.returnToAnchor(), 'Exact terminal selected');
  vscode.window.terminals = [];
  assert.equal(await controller.returnToAnchor(), 'Original terminal is closed');
});
