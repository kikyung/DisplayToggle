# Security Policy

## Reporting a vulnerability

Please report security problems privately through GitHub:
**Security → Report a vulnerability** on this repository.
Do not open a public issue for security reports.

## Scope

DisplayToggle runs locally, makes no network connections, and stores only a small
list of display names, UUIDs, and modes in `~/Library/Application Support/DisplayToggle/`.

The app calls the private CoreGraphics function `CGSConfigureDisplayEnabled`.
Behavior changes caused by macOS updates to that function are bugs, not vulnerabilities,
unless they lead to data loss or privilege escalation.
