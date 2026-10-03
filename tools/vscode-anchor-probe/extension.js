'use strict';

// In-memory only: this prototype never reads editor/terminal content or opens a socket.
function createController(vscode) {
  let anchor;

  function captureEditor() {
    const group = vscode.window.tabGroups.activeTabGroup;
    const tab = group?.activeTab;
    const editor = vscode.window.activeTextEditor;
    if (!(tab?.input instanceof vscode.TabInputText) ||
        !editor ||
        editor.document.uri.toString() !== tab.input.uri.toString() ||
        editor.viewColumn !== group.viewColumn) {
      anchor = undefined;
      return 'No active text editor tab to capture';
    }
    anchor = { kind: 'editor', tab };
    return 'Captured the current editor tab';
  }

  function captureTerminal() {
    const terminal = vscode.window.activeTerminal;
    if (!terminal || !vscode.window.terminals.includes(terminal)) {
      anchor = undefined;
      return 'No active terminal to capture';
    }
    anchor = { kind: 'terminal', terminal };
    return 'Captured the current terminal';
  }

  async function returnToAnchor() {
    if (!anchor) return 'No captured tab';
    if (anchor.kind === 'terminal') {
      if (!vscode.window.terminals.includes(anchor.terminal)) return 'Original terminal is closed';
      anchor.terminal.show(false);
      return vscode.window.activeTerminal === anchor.terminal
        ? 'Exact terminal selected' : 'Terminal focus unverified';
    }

    // Tab is a live object, not a URI alone. A closed tab must never be reopened.
    const group = vscode.window.tabGroups.all.find(group => group.tabs.includes(anchor.tab));
    if (!group) return 'Original editor tab is closed or identity changed';
    const input = anchor.tab.input;
    if (!(input instanceof vscode.TabInputText)) return 'Original tab is no longer a text editor';
    await vscode.window.showTextDocument(input.uri, {
      viewColumn: group.viewColumn,
      preserveFocus: false,
      preview: anchor.tab.isPreview
    });
    return vscode.window.tabGroups.activeTabGroup?.activeTab === anchor.tab
      ? 'Exact editor tab selected' : 'Editor focus unverified';
  }

  return { captureEditor, captureTerminal, returnToAnchor };
}

function activate(context) {
  const vscode = require('vscode');
  const controller = createController(vscode);
  for (const [command, action] of [
    ['charProbe.captureEditor', controller.captureEditor],
    ['charProbe.captureTerminal', controller.captureTerminal],
    ['charProbe.returnToAnchor', controller.returnToAnchor]
  ]) {
    context.subscriptions.push(vscode.commands.registerCommand(command, async () => {
      const result = await action();
      await vscode.window.showInformationMessage(result);
      return result;
    }));
  }
}

module.exports = { activate, createController };
