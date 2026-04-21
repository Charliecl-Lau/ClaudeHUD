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

---

## #2 — Statusline Not Updating on Each Prompt

**Date:** 2026-04-21

### Symptom
The statusline displayed static/zero values and never updated after each Claude Code response, mismatching expected live session data.

### Root Cause
A defensive regex in `statusline.ps1` was intended to fix unescaped backslashes in Windows paths before JSON parsing:

```powershell
$raw = $raw -replace '\\(?!["\\/bfnrt]|u[0-9a-fA-F]{4})', '\\'
```

Claude Code always sends valid JSON, so Windows paths are already properly escaped (e.g. `C:\\Users\\yeekw`). For any `\\` sequence in the raw string, the regex correctly left the first `\` alone (it is followed by `\`, which is in the allowed set), but then matched the second `\` — because the character after it (e.g. `U` in `Users`) is not a valid JSON escape character. It doubled that backslash, turning `C:\\Users` into `C:\\\Users`. This produced malformed JSON, causing `ConvertFrom-Json` to throw silently. With no parsed data, the script output nothing and the statusline froze.

### Fix
Removed the regex entirely. Claude Code's JSON output is always well-formed and requires no backslash pre-processing.

```powershell
# Before
$raw = $raw.TrimStart([char]0xFEFF)
$raw = $raw -replace '\\(?!["\\/bfnrt]|u[0-9a-fA-F]{4})', '\\'
$inputJson = $raw | ConvertFrom-Json

# After
$raw = $raw.TrimStart([char]0xFEFF)
$inputJson = $raw | ConvertFrom-Json
```

### Commit
`02a6dc8` — Fix statusline not updating due to backslash regex corrupting JSON
