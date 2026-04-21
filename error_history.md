# Error History

## #1 — Statusline Not Appearing in Claude Code

**Date:** 2026-04-21

### Symptom
The statusline was configured in `~/.claude/settings.json` but never appeared in Claude Code. No error message was shown — it silently did nothing.

### Root Cause
The config used Windows-style backslashes in the file path:

```json
"statusLine": {
  "type": "command",
  "command": "powershell -NoProfile -NonInteractive -File C:\\Users\\yeekw\\Documents\\ClaudeHUD\\statusline.ps1"
}
```

Claude Code spawns the statusline command through a bash-like shell (Git Bash on Windows). Bash interprets backslashes as escape characters before passing the command to PowerShell, so the file path was corrupted and the script could not be found.

### Fix
Replace backslashes with forward slashes in the path. PowerShell accepts forward slashes natively:

```json
"statusLine": {
  "type": "command",
  "command": "powershell -NoProfile -NonInteractive -File C:/Users/yeekw/Documents/ClaudeHUD/statusline.ps1"
}
```

### Verification
Running the command manually from bash with the corrected path produced the expected three-line output, and the statusline appeared correctly in Claude Code after restarting.
