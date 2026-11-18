# Windows entry point for macols-ai-coding-setup.
#
# install.sh is the single source of truth for argument parsing and tool
# selection, so this just finds Git for Windows Bash and hands every argument
# to it. WSL bash is not used: it would install into the WSL Linux home, not
# the Windows profile.
#
# Examples:
#   .\install.ps1
#   .\install.ps1 claudecode pi
#   .\install.ps1 codex --skills-only --no-cli

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-GitBash {
    $Candidates = @(
        "$env:ProgramFiles\Git\bin\bash.exe",
        "${env:ProgramFiles(x86)}\Git\bin\bash.exe",
        "$env:LOCALAPPDATA\Programs\Git\bin\bash.exe"
    )
    $Git = Get-Command git -ErrorAction SilentlyContinue
    if ($Git) {
        # git.exe lives in <GitRoot>\cmd or <GitRoot>\bin.
        $Candidates += Join-Path (Split-Path (Split-Path $Git.Source)) "bin\bash.exe"
    }
    foreach ($Candidate in $Candidates) {
        if ($Candidate -and (Test-Path -LiteralPath $Candidate)) { return $Candidate }
    }
    return $null
}

$Bash = Get-GitBash
if (-not $Bash) {
    Write-Host "Git for Windows Bash is required. Install Git for Windows, then re-run this script." -ForegroundColor Red
    exit 1
}

$InstallSh = (Join-Path $PSScriptRoot "install.sh") -replace "\\", "/"
& $Bash $InstallSh @args
exit $LASTEXITCODE
