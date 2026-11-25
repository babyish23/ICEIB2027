[CmdletBinding()]
param(
    [string]$GitUrl,
    [string]$FolderName = "trailguard-tw-paper",
    [string]$McpName,
    [string]$BaseDir = (Join-Path $env:USERPROFILE "overleaf-projects"),
    [string]$SourceTex = (Join-Path $PSScriptRoot "trailguard_ieee.tex"),
    [switch]$NonInteractive,
    [switch]$SkipInstall
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

function Write-Step {
    param([string]$Message)
    Write-Host "`n==> $Message" -ForegroundColor Cyan
}

function Refresh-ProcessPath {
    $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $localBin = Join-Path $env:USERPROFILE ".local\bin"
    $env:Path = "$machinePath;$userPath;$localBin"
}

function Assert-LastExitCode {
    param([string]$Action)
    if ($LASTEXITCODE -ne 0) {
        throw "$Action failed with exit code $LASTEXITCODE."
    }
}

function Install-WinGetPackage {
    param(
        [string]$Id,
        [string]$DisplayName
    )

    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        throw "WinGet is required to install $DisplayName automatically."
    }

    Write-Host "Installing $DisplayName..." -ForegroundColor Yellow
    & winget install --id $Id --exact --source winget `
        --accept-package-agreements --accept-source-agreements
    Assert-LastExitCode "Installing $DisplayName"
    Refresh-ProcessPath
}

function Ensure-Dependencies {
    Write-Step "Checking Git, uvx, and Claude Code"

    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        if ($SkipInstall) { throw "Git is missing and -SkipInstall was used." }
        Install-WinGetPackage -Id "Git.Git" -DisplayName "Git for Windows"
    }

    if (-not (Get-Command uvx -ErrorAction SilentlyContinue)) {
        if ($SkipInstall) { throw "uvx is missing and -SkipInstall was used." }
        Install-WinGetPackage -Id "astral-sh.uv" -DisplayName "uv"
    }

    if (-not (Get-Command claude -ErrorAction SilentlyContinue)) {
        if ($SkipInstall) {
            throw "Claude Code is missing and -SkipInstall was used."
        }
        Install-WinGetPackage -Id "Anthropic.ClaudeCode" `
            -DisplayName "Claude Code"
    }

    foreach ($command in @("git", "uvx", "claude")) {
        if (-not (Get-Command $command -ErrorAction SilentlyContinue)) {
            throw "'$command' is still unavailable. Open a new PowerShell window and rerun this script."
        }
    }

    Write-Host "Git:    $(& git --version)" -ForegroundColor Green
    Write-Host "uvx:    $(& uvx --version)" -ForegroundColor Green
    Write-Host "Claude: $(& claude --version)" -ForegroundColor Green
}

function Resolve-Inputs {
    if ([string]::IsNullOrWhiteSpace($GitUrl)) {
        if ($NonInteractive) {
            throw "-GitUrl is required when -NonInteractive is used."
        }
        $script:GitUrl = Read-Host "Overleaf Git URL (https://git.overleaf.com/...)"
    }

    $script:GitUrl = $GitUrl.Trim()
    $parsedUri = $null
    $validUri = [Uri]::TryCreate($GitUrl, [UriKind]::Absolute, [ref]$parsedUri)
    if (-not $validUri -or
        $parsedUri.Scheme -ne "https" -or
        $parsedUri.Host -ne "git.overleaf.com" -or
        $parsedUri.AbsolutePath.Trim("/") -eq "") {
        throw "Invalid Overleaf Git URL. Expected https://git.overleaf.com/<project-id>."
    }

    $script:FolderName = $FolderName.Trim()
    if ([string]::IsNullOrWhiteSpace($FolderName) -or
        $FolderName -in @(".", "..") -or
        $FolderName.IndexOfAny([IO.Path]::GetInvalidFileNameChars()) -ge 0 -or
        $FolderName.Contains("\") -or
        $FolderName.Contains("/")) {
        throw "FolderName must be one valid folder name."
    }

    if ([string]::IsNullOrWhiteSpace($McpName)) {
        $script:McpName = "overleaf-$FolderName"
    } else {
        $script:McpName = $McpName.Trim()
    }

    if ($McpName -notmatch "^[A-Za-z0-9._-]+$") {
        throw "McpName may contain only letters, numbers, dot, underscore, and hyphen."
    }
}

function Sync-OverleafRepository {
    Write-Step "Preparing the local Overleaf repository"

    New-Item -ItemType Directory -Force -Path $BaseDir | Out-Null
    $script:TargetDir = Join-Path $BaseDir $FolderName

    if (Test-Path $TargetDir) {
        & git -C $TargetDir rev-parse --is-inside-work-tree 2>$null | Out-Null
        Assert-LastExitCode "Validating existing repository '$TargetDir'"

        $origin = (& git -C $TargetDir remote get-url origin).Trim()
        Assert-LastExitCode "Reading the existing origin"
        if ($origin -ne $GitUrl) {
            throw "Existing repository origin '$origin' does not match '$GitUrl'."
        }

        & git -C $TargetDir pull --ff-only
        Assert-LastExitCode "Updating the Overleaf repository"
    } else {
        & git clone -- $GitUrl $TargetDir
        Assert-LastExitCode "Cloning the Overleaf repository"
    }

    Write-Host "Repository: $TargetDir" -ForegroundColor Green
}

function Seed-Paper {
    if (-not (Test-Path -LiteralPath $SourceTex -PathType Leaf)) {
        Write-Warning "Source paper not found at '$SourceTex'; skipping paper copy."
        return
    }

    Write-Step "Copying the TrailGuard TW paper into the Overleaf project"
    $destination = Join-Path $TargetDir "trailguard_ieee.tex"
    Copy-Item -LiteralPath $SourceTex -Destination $destination -Force
    Write-Host "Paper: $destination" -ForegroundColor Green
    Write-Host "Set trailguard_ieee.tex as the Main document in Overleaf." -ForegroundColor Yellow
}

function Register-GitMcp {
    Write-Step "Registering the repository as a user-scoped Claude Code MCP server"

    $mcpList = (& claude mcp list 2>&1 | Out-String)
    if ($mcpList -match "(?m)^\s*$([regex]::Escape($McpName))\s*:") {
        & claude mcp remove --scope user $McpName
        Assert-LastExitCode "Removing the existing MCP registration"
    }

    & claude mcp add --scope user --transport stdio $McpName -- `
        uvx mcp-server-git --repository $TargetDir
    Assert-LastExitCode "Registering the MCP server"

    & claude mcp get $McpName
    Assert-LastExitCode "Verifying the MCP registration"
}

try {
    Write-Host "TrailGuard TW Overleaf + Claude Code MCP Setup" -ForegroundColor Cyan
    Refresh-ProcessPath
    Ensure-Dependencies
    Resolve-Inputs
    Sync-OverleafRepository
    Seed-Paper
    Register-GitMcp

    Write-Host "`nSetup complete." -ForegroundColor Green
    Write-Host "Next steps:" -ForegroundColor Cyan
    Write-Host "  1. Sign in once by running: claude"
    Write-Host "  2. Open the Overleaf project and select trailguard_ieee.tex as Main document."
    Write-Host "  3. Review changes, then commit and push them from '$TargetDir'."
} catch {
    Write-Host "`nSetup failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
