// Copyright 2024 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:agents/agents.dart';

/// The [ShellPolicy] configured agents run `run_shell` under.
///
/// Deny-list only, and deliberately short. An allow-list would break the
/// tool's general-purpose terminal character, and the policy class itself is
/// documented as a UX guardrail rather than a security boundary — the real
/// controls are the per-command approval prompt and, in sandboxed builds,
/// the App Sandbox the spawned shell inherits. What belongs here is the
/// small set of commands that are near-certainly a mistake no matter who
/// typed them.
///
/// Every pattern is anchored to a command position (start of input or right
/// after `;`, `&`, `|`, or a newline) so that mentioning a dangerous command
/// as an argument — `grep "rm -rf" notes.md` — passes untouched.
ShellPolicy defaultShellPolicy() => ShellPolicy(
  denyList: [
    // Elevation cannot succeed from a sandboxed app anyway; failing fast
    // with a policy reason beats a password prompt hanging the session.
    r'(^|[\n;&|]\s*)sudo(\s|$)',
    // rm aimed at a filesystem root or the whole home directory. Deeper
    // targets (`rm -rf build/`) are legitimate daily use and stay allowed;
    // the approval prompt is the control for those.
    r'''(^|[\n;&|]\s*)rm\s+(-{1,2}\S+\s+)*["']?(/|~|\$HOME)/?\*?["']?\s*($|[;&|])''',
    // Filesystem and disk destruction.
    r'(^|[\n;&|]\s*)mkfs(\.|\s|$)',
    r'(^|[\n;&|]\s*)diskutil\s+(erase\w*|apfs\s+delete\w*)',
    r'(^|[\n;&|]\s*)dd\s+[^;&|]*\bof=/dev/',
    // Host power state and service teardown.
    r'(^|[\n;&|]\s*)(shutdown|reboot|halt)(\s|$)',
    r'(^|[\n;&|]\s*)launchctl\s+(bootout|unload)(\s|$)',
    // The classic fork bomb.
    r':\(\)\s*\{\s*:\s*\|\s*:\s*&\s*\}\s*;\s*:',
    // Piping a download straight into a shell.
    r'(curl|wget)\b[^;&|]*\|\s*(ba|z|da)?sh\b',
    // Keychain exfiltration.
    r'(^|[\n;&|]\s*)security\s+(dump-keychain|find-generic-password|'
        r'find-internet-password)',
  ],
);
