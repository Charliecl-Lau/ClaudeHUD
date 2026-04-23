# Set UTF-8 for both input and output
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding  = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

# Read input from stdin and strip BOM if present
$raw = [Console]::In.ReadToEnd()
$raw = $raw.TrimStart([char]0xFEFF)
$inputJson = $raw | ConvertFrom-Json

# Parse JSON
$MODEL = if ($inputJson.model.display_name) { $inputJson.model.display_name } else { "Claude" }
$DIR = $inputJson.workspace.current_dir
$COST = if ($inputJson.cost.total_cost_usd) { $inputJson.cost.total_cost_usd } else { 0 }
$PCT = if ($inputJson.context_window.used_percentage) { [math]::Floor($inputJson.context_window.used_percentage) } else { 0 }
$CTX_SIZE = $inputJson.context_window.context_window_size
$DURATION_MS = if ($inputJson.cost.total_duration_ms) { $inputJson.cost.total_duration_ms } else { 0 }
$LINES_ADD = $inputJson.cost.total_lines_added
$LINES_DEL = $inputJson.cost.total_lines_removed
$AGENT = $inputJson.agent.name
$VERSION = $inputJson.version
$VIM_MODE = $inputJson.vim.mode

# Rate limits
$RATE_5H = $inputJson.rate_limits.five_hour.used_percentage
$RATE_7D = $inputJson.rate_limits.seven_day.used_percentage
$RESET_5H = $inputJson.rate_limits.five_hour.resets_at
$RESET_7D = $inputJson.rate_limits.seven_day.resets_at

# Tokens
$TOTAL_IN = $inputJson.context_window.total_input_tokens
$TOTAL_OUT = $inputJson.context_window.total_output_tokens
$CACHE_READ = $inputJson.context_window.current_usage.cache_read_input_tokens
$CACHE_CREATE = $inputJson.context_window.current_usage.cache_creation_input_tokens
$CUR_INPUT = $inputJson.context_window.current_usage.input_tokens
$API_DUR_MS = if ($inputJson.cost.total_api_duration_ms) { $inputJson.cost.total_api_duration_ms } else { 0 }

# Colors
$ESC = [char]27
$RESET   = "$ESC[0m"
$BOLD    = "$ESC[1m"
$DIM     = "$ESC[2m"
$CYAN    = "$ESC[36m"
$GREEN   = "$ESC[32m"
$YELLOW  = "$ESC[33m"
$RED     = "$ESC[31m"
$MAGENTA = "$ESC[35m"
$BLUE    = "$ESC[34m"
$WHITE   = "$ESC[37m"
$SEP     = "${DIM} | ${RESET}"
$CLEAR = "$ESC[K"

# Helper: color by percentage
function Get-ColorPct($val) {
    if ($val -ge 80) { return $RED }
    if ($val -ge 50) { return $YELLOW }
    return $GREEN
}

# Helper: format duration from ms
function Format-Duration($ms) {
    $total_sec = [math]::Floor($ms / 1000)
    if ($total_sec -le 0) { return "0s" }
    $h = [int][math]::Floor($total_sec / 3600)
    $m = [int][math]::Floor(($total_sec % 3600) / 60)
    $s = [int]($total_sec % 60)
    if ($h -gt 0) { return "{0}h {1:D2}m" -f $h, $m }
    if ($m -gt 0) { return "{0}m {1:D2}s" -f $m, $s }
    return "{0}s" -f $s
}

# Helper: format countdown from epoch
function Format-Countdown($reset_at) {
    if (-not $reset_at -or $reset_at -eq "null") { return "" }
    $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $diff = [long]$reset_at - $now
    if ($diff -le 0) { return "now" }
    $h = [math]::Floor($diff / 3600)
    $m = [math]::Floor(($diff % 3600) / 60)
    return "{0}h {1}m" -f $h, $m
}

# Helper: format token count
function Format-Tokens($t) {
    if (-not $t -or $t -eq 0) { return "0" }
    if ($t -ge 1000000) { return "{0:N1}M" -f ($t / 1000000) }
    if ($t -ge 1000)    { return "{0:N1}K" -f ($t / 1000) }
    return "$t"
}

# Context window size label
$CTX_LABEL = ""
if ($CTX_SIZE) {
    if ($CTX_SIZE -ge 1000000) { $CTX_LABEL = "${DIM}1M${RESET}" }
    else                        { $CTX_LABEL = "${DIM}200K${RESET}" }
}

# Git info
$BRANCH = ""
$REPO_LINK = if ($DIR) { Split-Path $DIR -Leaf } else { "work" }
$null = git rev-parse --git-dir 2>$null
if ($LASTEXITCODE -eq 0) {
    $BRANCH = git branch --show-current 2>$null
    $REMOTE = git remote get-url origin 2>$null
    if ($REMOTE) {
        $REMOTE = $REMOTE -replace 'git@github\.com:', 'https://github.com/' -replace '\.git$', ''
        $REPO_NAME = Split-Path $REMOTE -Leaf
        # Hyperlink (supported in Windows Terminal)
        $REPO_LINK = "$ESC]8;;$REMOTE$([char]7)$REPO_NAME$ESC]8;;$([char]7)"
    }
}

# Context bar
$BAR_COLOR = Get-ColorPct $PCT
$FILLED = [math]::Floor($PCT * 15 / 100)
$EMPTY  = 15 - $FILLED
$BAR = ($BAR_COLOR + ([string][char]0x25A0) * $FILLED) + ($DIM + ([string][char]0x25A1) * $EMPTY) + $RESET

# Git file stats
$GIT_STATS = ""
$null = git rev-parse --git-dir 2>$null
if ($LASTEXITCODE -eq 0) {
    $GIT_M = (git diff --name-only 2>$null | Measure-Object).Count
    $GIT_A = (git ls-files --others --exclude-standard 2>$null | Measure-Object).Count
    $GIT_D = (git diff --diff-filter=D --name-only 2>$null | Measure-Object).Count
    $parts = @()
    if ($GIT_M -gt 0) { $parts += "${YELLOW}${GIT_M}M${RESET}" }
    if ($GIT_A -gt 0) { $parts += "${GREEN}${GIT_A}A${RESET}" }
    if ($GIT_D -gt 0) { $parts += "${RED}${GIT_D}D${RESET}" }
    $GIT_STATS = $parts -join " "
}

# Cache hit rate
$CACHE_HIT = ""
$CACHE_CREATE_INT = if ($CACHE_CREATE) { [long]$CACHE_CREATE } else { 0 }
$CUR_INPUT_INT    = if ($CUR_INPUT)    { [long]$CUR_INPUT }    else { 0 }
$CACHE_READ_INT   = if ($CACHE_READ)   { [long]$CACHE_READ }   else { 0 }
$CACHE_TOTAL = $CACHE_READ_INT + $CUR_INPUT_INT + $CACHE_CREATE_INT
if ($CACHE_TOTAL -gt 0) {
    $C_PCT = [math]::Floor($CACHE_READ_INT * 100 / $CACHE_TOTAL)
    $C_CLR = Get-ColorPct (100 - $C_PCT)
    $CACHE_HIT = "${DIM}cache${RESET} ${C_CLR}${C_PCT}%${RESET}"
}

# LINE 1: Model + Context size + Version + Repo + Branch + Lines + Files + Agent
$L1 = "${CYAN}${BOLD}${MODEL}${RESET}"
if ($CTX_LABEL)  { $L1 += " $CTX_LABEL" }
if ($VERSION)    { $L1 += " ${DIM}v$VERSION${RESET}" }
$L1 += "${SEP}${WHITE}${REPO_LINK}${RESET}"
if ($BRANCH)     { $L1 += " ${DIM}($BRANCH)${RESET}" }

$LINES_PART = ""
if ($LINES_ADD -and $LINES_ADD -ne 0) { $LINES_PART = "${GREEN}+${LINES_ADD}${RESET}" }
if ($LINES_DEL -and $LINES_DEL -ne 0) {
    if ($LINES_PART) { $LINES_PART += " ${RED}-${LINES_DEL}${RESET}" }
    else             { $LINES_PART  = "${RED}-${LINES_DEL}${RESET}" }
}
if ($LINES_PART) { $L1 += "${SEP}${LINES_PART} ${DIM}lines${RESET}" }
if ($GIT_STATS)  { $L1 += "${SEP}${GIT_STATS}" }
if ($AGENT)      { $L1 += "${SEP}${MAGENTA}${AGENT}${RESET}" }
if ($VIM_MODE) {
    if ($VIM_MODE -eq "NORMAL") { $L1 += "${SEP}${BLUE}${BOLD}NOR${RESET}" }
    else                         { $L1 += "${SEP}${GREEN}${BOLD}INS${RESET}" }
}

# LINE 2: Context bar + Cost + Duration + Rate limits
$DUR = Format-Duration $DURATION_MS
$COST_FMT = '$' + ("{0:N2}" -f $COST)
$L2 = "${BAR} ${DIM}${PCT}%${RESET}${SEP}${YELLOW}${COST_FMT}${RESET}${SEP}${DIM}${DUR}${RESET}"

if ($null -ne $RATE_5H) {
    $R5_INT = [math]::Floor($RATE_5H)
    $R5_C   = Get-ColorPct $R5_INT
    $L2    += "${SEP}${DIM}5h${RESET} ${R5_C}${R5_INT}%${RESET}"
    if ($RESET_5H -and $RESET_5H -ne "null") {
        $R5_CD = Format-Countdown $RESET_5H
        $L2   += " ${DIM}(${R5_CD})${RESET}"
    }
}
if ($null -ne $RATE_7D) {
    $R7_INT = [math]::Floor($RATE_7D)
    $R7_C   = Get-ColorPct $R7_INT
    $L2    += "${SEP}${DIM}7d${RESET} ${R7_C}${R7_INT}%${RESET}"
    if ($RESET_7D -and $RESET_7D -ne "null") {
        $R7_CD = Format-Countdown $RESET_7D
        $L2   += " ${DIM}(${R7_CD})${RESET}"
    }
}

# LINE 3: Cache hit rate + Tokens + API wait + Current token detail
$L3 = ""
if ($CACHE_HIT) { $L3 = $CACHE_HIT }

$IN_FMT  = Format-Tokens $TOTAL_IN
$OUT_FMT = Format-Tokens $TOTAL_OUT
$TOKENS_PART = "${DIM}in:${RESET} ${CYAN}${IN_FMT}${RESET} ${DIM}out:${RESET} ${MAGENTA}${OUT_FMT}${RESET}"
if ($L3) { $L3 += "${SEP}${TOKENS_PART}" } else { $L3 = $TOKENS_PART }

$API_DUR = Format-Duration $API_DUR_MS
if ($DURATION_MS -gt 0 -and $API_DUR_MS -gt 0) {
    $API_PCT = [math]::Floor($API_DUR_MS * 100 / $DURATION_MS)
    $L3 += "${SEP}${DIM}api wait${RESET} ${CYAN}${API_DUR}${RESET} ${DIM}(${API_PCT}%)${RESET}"
} else {
    $L3 += "${SEP}${DIM}api wait${RESET} ${CYAN}${API_DUR}${RESET}"
}

$CUR_IN_FMT    = Format-Tokens $CUR_INPUT
$CACHE_R_FMT   = Format-Tokens $CACHE_READ
$CACHE_C_FMT   = Format-Tokens $CACHE_CREATE
$L3 += "${SEP}${DIM}cur${RESET} ${CUR_IN_FMT} ${DIM}in${RESET} ${CACHE_R_FMT} ${DIM}read${RESET} ${CACHE_C_FMT} ${DIM}write${RESET}"

# Output
Write-Host "$L1"
Write-Host "$L2"
Write-Host "$L3"
