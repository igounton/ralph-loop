#!/usr/bin/env node

/**
 * Tests for bin/lib/settings.js
 * Uses Node's built-in test runner (node:test + node:assert)
 */

const { describe, it, beforeEach, afterEach } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const path = require('path');
const os = require('os');
const { mergeHooks, mergeSettings } = require('../bin/lib/settings');

let tmpDir;

beforeEach(() => {
  tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'ralph-settings-'));
});

afterEach(() => {
  fs.rmSync(tmpDir, { recursive: true, force: true });
});

function writeJson(filePath, obj) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, JSON.stringify(obj, null, 2), 'utf8');
}

function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, 'utf8'));
}

const RALPH_SETTINGS = {
  permissions: { deny: ['Read(.agent/history/**)'], allow: ['**'] },
  defaultMode: 'acceptEdits',
  enableAllProjectMcpServers: true,
  hooks: {
    PostToolUse: [
      { matcher: 'Edit|Write|Bash', hooks: [{ type: 'command', command: 'node $CLAUDE_PROJECT_DIR/.claude/hooks/post-tool-use.js' }] },
      { matcher: 'Bash', hooks: [{ type: 'command', command: 'node $CLAUDE_PROJECT_DIR/.claude/hooks/one-task-guard.js' }] },
    ],
    Notification: [
      { matcher: '', hooks: [{ type: 'command', command: 'node $CLAUDE_PROJECT_DIR/.claude/hooks/play-sound.js notification' }] },
    ],
  },
};

// --- mergeHooks unit tests ---

describe('mergeHooks', () => {
  it('returns source hooks when existing is empty', () => {
    const result = mergeHooks({}, RALPH_SETTINGS.hooks);
    assert.deepEqual(result, RALPH_SETTINGS.hooks);
  });

  it('returns source hooks when existing is undefined', () => {
    const result = mergeHooks(undefined, RALPH_SETTINGS.hooks);
    assert.deepEqual(result, RALPH_SETTINGS.hooks);
  });

  it('preserves existing hooks and adds new event types', () => {
    const existing = {
      PreToolUse: [{ matcher: 'Bash', hooks: [{ type: 'command', command: 'echo pre' }] }],
    };
    const result = mergeHooks(existing, RALPH_SETTINGS.hooks);
    assert.equal(result.PreToolUse.length, 1);
    assert.equal(result.PostToolUse.length, 2);
    assert.equal(result.Notification.length, 1);
  });

  it('does not duplicate hooks with same command', () => {
    const existing = { ...RALPH_SETTINGS.hooks };
    const result = mergeHooks(existing, RALPH_SETTINGS.hooks);
    assert.equal(result.PostToolUse.length, 2);
    assert.equal(result.Notification.length, 1);
  });

  it('adds hooks with different commands to same event type', () => {
    const existing = {
      PostToolUse: [
        { matcher: 'Bash', hooks: [{ type: 'command', command: 'echo custom' }] },
      ],
    };
    const result = mergeHooks(existing, RALPH_SETTINGS.hooks);
    assert.equal(result.PostToolUse.length, 3);
  });

  it('does not mutate the existing object', () => {
    const existing = {
      PostToolUse: [{ matcher: 'Bash', hooks: [{ type: 'command', command: 'echo custom' }] }],
    };
    const copy = JSON.parse(JSON.stringify(existing));
    mergeHooks(existing, RALPH_SETTINGS.hooks);
    assert.deepEqual(existing, copy);
  });

  it('skips non-array source entries', () => {
    const result = mergeHooks({}, { PostToolUse: 'invalid' });
    assert.deepEqual(result, {});
  });
});

// --- mergeSettings integration tests ---

describe('mergeSettings', () => {
  it('creates settings when dest does not exist', () => {
    const src = path.join(tmpDir, 'source', 'settings.json');
    const dest = path.join(tmpDir, 'target', '.claude', 'settings.json');
    writeJson(src, RALPH_SETTINGS);

    const result = mergeSettings(src, dest);
    assert.equal(result.created, true);
    assert.equal(result.merged, false);
    assert.equal(result.backedUp, false);
    assert.deepEqual(readJson(dest), RALPH_SETTINGS);
  });

  it('merges hooks into existing settings preserving user prefs', () => {
    const src = path.join(tmpDir, 'source', 'settings.json');
    const dest = path.join(tmpDir, 'target', 'settings.json');

    writeJson(src, RALPH_SETTINGS);
    writeJson(dest, {
      permissions: { deny: [], allow: ['Read'] },
      defaultMode: 'plan',
      customSetting: true,
    });

    const result = mergeSettings(src, dest);
    assert.equal(result.merged, true);

    const merged = readJson(dest);
    assert.equal(merged.defaultMode, 'plan');
    assert.deepEqual(merged.permissions, { deny: [], allow: ['Read'] });
    assert.equal(merged.customSetting, true);
    assert.equal(merged.enableAllProjectMcpServers, true);
    assert.equal(merged.hooks.PostToolUse.length, 2);
    assert.equal(merged.hooks.Notification.length, 1);
  });

  it('does not duplicate hooks on repeated installs', () => {
    const src = path.join(tmpDir, 'source', 'settings.json');
    const dest = path.join(tmpDir, 'target', 'settings.json');

    writeJson(src, RALPH_SETTINGS);
    writeJson(dest, RALPH_SETTINGS);

    mergeSettings(src, dest);
    const merged = readJson(dest);
    assert.equal(merged.hooks.PostToolUse.length, 2);
    assert.equal(merged.hooks.Notification.length, 1);
  });

  it('backs up and replaces malformed JSON', () => {
    const src = path.join(tmpDir, 'source', 'settings.json');
    const dest = path.join(tmpDir, 'target', 'settings.json');

    writeJson(src, RALPH_SETTINGS);
    fs.mkdirSync(path.dirname(dest), { recursive: true });
    fs.writeFileSync(dest, '{ broken json !!!', 'utf8');

    const result = mergeSettings(src, dest);
    assert.equal(result.backedUp, true);
    assert.ok(fs.existsSync(dest + '.bak'));
    assert.deepEqual(readJson(dest), RALPH_SETTINGS);
  });

  it('backs up and replaces empty file', () => {
    const src = path.join(tmpDir, 'source', 'settings.json');
    const dest = path.join(tmpDir, 'target', 'settings.json');

    writeJson(src, RALPH_SETTINGS);
    fs.mkdirSync(path.dirname(dest), { recursive: true });
    fs.writeFileSync(dest, '', 'utf8');

    const result = mergeSettings(src, dest);
    assert.equal(result.backedUp, true);
    assert.deepEqual(readJson(dest), RALPH_SETTINGS);
  });

  it('returns early if source does not exist', () => {
    const src = path.join(tmpDir, 'nonexistent', 'settings.json');
    const dest = path.join(tmpDir, 'target', 'settings.json');

    const result = mergeSettings(src, dest);
    assert.equal(result.created, false);
    assert.equal(result.merged, false);
    assert.equal(result.backedUp, false);
  });

  it('merges existing user hooks with ralph hooks', () => {
    const src = path.join(tmpDir, 'source', 'settings.json');
    const dest = path.join(tmpDir, 'target', 'settings.json');

    writeJson(src, RALPH_SETTINGS);
    writeJson(dest, {
      hooks: {
        PostToolUse: [
          { matcher: 'Bash', hooks: [{ type: 'command', command: 'echo my-custom-hook' }] },
        ],
        PreToolUse: [
          { matcher: 'Write', hooks: [{ type: 'command', command: 'echo pre-write' }] },
        ],
      },
    });

    mergeSettings(src, dest);
    const merged = readJson(dest);

    assert.equal(merged.hooks.PostToolUse.length, 3);
    assert.equal(merged.hooks.PreToolUse.length, 1);
    assert.equal(merged.hooks.Notification.length, 1);
  });
});
