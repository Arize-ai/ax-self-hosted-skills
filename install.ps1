#Requires -Version 5.1
<#
.SYNOPSIS
    Arize Self-Hosted Skills Installer for Windows

.DESCRIPTION
    Installs agent skills from this repo into project or global skill
    directories. PowerShell equivalent of install.sh. Does not install
    Arize AX or the ax CLI.

.EXAMPLE
    .\install.ps1 -List
    .\install.ps1 -Project ~/my-app
    .\install.ps1 -Project . -Skill arize-alerts-troubleshoot
    .\install.ps1 -Global
    .\install.ps1 -Project ~/my-app -Copy
    .\install.ps1 -Project ~/my-app -Uninstall
#>

[CmdletBinding()]
param(
    [string]$Project,
    [switch]$Global,
    [switch]$Copy,
    [switch]$Force,
    [switch]$SkipCli,  # accepted for compatibility; this repo does not install ax CLI
    [string[]]$Agent,
    [string[]]$Skill,
    [switch]$Yes,
    [switch]$Uninstall,
    [switch]$List
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$SkillsSrc = Join-Path $ScriptDir "skills"

# --- List mode ---

if ($List) {
    Write-Host "Available skills:"
    Get-ChildItem -Path $SkillsSrc -Directory | ForEach-Object {
        Write-Host "  $($_.Name)"
    }
    exit 0
}

# --- Validate --Skill names ---

if ($Skill.Count -gt 0) {
    foreach ($name in $Skill) {
        $skillPath = Join-Path $SkillsSrc $name
        if (-not (Test-Path $skillPath -PathType Container)) {
            Write-Host "Error: unknown skill '$name'"
            Write-Host ""
            Write-Host "Available skills:"
            Get-ChildItem -Path $SkillsSrc -Directory | ForEach-Object {
                Write-Host "  $($_.Name)"
            }
            exit 1
        }
    }
}

# --- Agent detection ---

function Get-AgentSkillsDir {
    param([string]$AgentName, [string]$Base)
    switch ($AgentName) {
        "cursor"  { Join-Path $Base ".cursor\skills" }
        "claude"  { Join-Path $Base ".claude\skills" }
        "codex"   { Join-Path $Base ".codex\skills" }
        "copilot" { Join-Path $Base ".agents\skills" }
        default   { Join-Path $Base ".$AgentName\skills" }
    }
}

function Find-Agents {
    param([string]$Base)
    $found = @()
    if (Test-Path (Join-Path $Base ".cursor"))         { $found += "cursor" }
    if (Test-Path (Join-Path $Base ".claude"))         { $found += "claude" }
    if (Test-Path (Join-Path $Base ".codex"))          { $found += "codex" }
    if (Test-Path (Join-Path $Base ".github\copilot")) { $found += "copilot" }
    return $found
}

if (-not $Global -and -not $Project) {
    Write-Host "Error: -Project <dir> is required (or use -Global for global install)."
    Write-Host ""
    Write-Host "Usage: .\install.ps1 -Project <dir> [flags]"
    Write-Host "       .\install.ps1 -Global [flags]"
    Write-Host "       .\install.ps1 -List"
    exit 1
}

$Agents = @()

if ($Agent.Count -gt 0) {
    $Agents = $Agent
} elseif ($Global) {
    $Agents = Find-Agents $HOME
} else {
    $resolved = Resolve-Path $Project -ErrorAction SilentlyContinue
    if ($resolved) {
        $Agents = Find-Agents $resolved.Path
    } else {
        $Agents = Find-Agents $Project
    }
}

if ($Agents.Count -eq 0) {
    if (-not $Yes) {
        Write-Host "No agents detected (looked for .cursor/, .claude/, .codex/, .github/copilot/ directories and cursor/claude/codex binaries)."
        Write-Host ""
        Write-Host "Which agent(s) are you using?"
        Write-Host "  1) cursor"
        Write-Host "  2) claude"
        Write-Host "  3) codex"
        Write-Host "  4) copilot (GitHub Copilot)"
        Write-Host ""
        $choices = Read-Host "Enter number(s) separated by spaces [1]"
        if (-not $choices) { $choices = "1" }
        foreach ($choice in $choices -split '\s+') {
            switch ($choice) {
                "1" { $Agents += "cursor" }
                "2" { $Agents += "claude" }
                "3" { $Agents += "codex" }
                "4" { $Agents += "copilot" }
                default { Write-Host "Unknown choice: $choice"; exit 1 }
            }
        }
    } else {
        Write-Host "No agents detected (looked for .cursor/, .claude/, .codex/, .github/copilot/ directories and cursor/claude/codex binaries)."
        Write-Host "Use -Agent <name> to specify manually, e.g.: .\install.ps1 -Agent cursor"
        exit 1
    }
}

# --- Resolve base directory ---

if ($Global) {
    $Base = $HOME
} else {
    $Base = $Project
}

# Resolve to absolute path
if (-not [System.IO.Path]::IsPathRooted($Base)) {
    $Base = Join-Path (Get-Location).Path $Base
}
$Base = [System.IO.Path]::GetFullPath($Base)

Write-Host "Arize Self-Hosted Skills Installer"
Write-Host "======================"
Write-Host ""
Write-Host "Detected agents: $($Agents -join ', ')"
if ($Global) {
    Write-Host "Scope: global ($HOME)"
} else {
    Write-Host "Scope: project ($Base)"
}
Write-Host ""

# --- Install or uninstall ---

function Install-Skill {
    param([string]$SkillSrc, [string]$Target)
    $skillName = Split-Path -Leaf $SkillSrc

    if (Test-Path $Target) {
        if ($Force) {
            Remove-Item -Recurse -Force $Target
        } else {
            Write-Host "  Skipped $skillName (already exists, use -Force to overwrite)"
            return
        }
    }

    if ($Copy) {
        Copy-Item -Recurse -Path $SkillSrc -Destination $Target
        Write-Host "  Copied  $skillName -> $Target"
    } else {
        # On Windows, directory symlinks require special handling
        # Try symbolic link first, fall back to directory junction
        try {
            New-Item -ItemType SymbolicLink -Path $Target -Target $SkillSrc -ErrorAction Stop | Out-Null
            Write-Host "  Linked  $skillName -> $Target"
        } catch {
            # Symbolic links may require admin/developer mode on Windows
            # Fall back to directory junction which doesn't require elevation
            try {
                cmd /c mklink /J "$Target" "$SkillSrc" 2>&1 | Out-Null
                Write-Host "  Linked  $skillName -> $Target (junction)"
            } catch {
                Write-Host "  Warning: Could not create symlink for $skillName. Copying instead."
                Copy-Item -Recurse -Path $SkillSrc -Destination $Target
                Write-Host "  Copied  $skillName -> $Target"
            }
        }
    }
}

function Uninstall-Skill {
    param([string]$SkillSrc, [string]$Target)
    $skillName = Split-Path -Leaf $SkillSrc

    if (-not (Test-Path $Target)) { return }

    $item = Get-Item $Target -Force
    $isLink = ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0

    if ($isLink) {
        # Check if this link points to our source
        $linkTarget = $item.Target
        # Junctions use a different format, normalize paths for comparison
        $normalizedSrc = [System.IO.Path]::GetFullPath($SkillSrc)
        if ($linkTarget -and ([System.IO.Path]::GetFullPath($linkTarget) -eq $normalizedSrc)) {
            Remove-Item $Target -Force
            Write-Host "  Removed $skillName ($Target)"
        } else {
            Write-Host "  Skipped $skillName (symlink points elsewhere)"
        }
    } elseif ($item.PSIsContainer) {
        Write-Host "  Skipped $skillName (is a directory, not a symlink from this repo)"
    }
}

# Build list of skills to process
$SkillDirs = @()
if ($Skill.Count -gt 0) {
    foreach ($name in $Skill) {
        $SkillDirs += Join-Path $SkillsSrc $name
    }
} else {
    Get-ChildItem -Path $SkillsSrc -Directory | ForEach-Object {
        $SkillDirs += $_.FullName
    }
}

foreach ($agentName in $Agents) {
    $skillsDir = Get-AgentSkillsDir -AgentName $agentName -Base $Base
    if (-not (Test-Path $skillsDir)) {
        New-Item -ItemType Directory -Path $skillsDir -Force | Out-Null
    }
    Write-Host "Agent: $agentName ($skillsDir)"

    foreach ($skillDir in $SkillDirs) {
        if (-not (Test-Path $skillDir -PathType Container)) { continue }
        $target = Join-Path $skillsDir (Split-Path -Leaf $skillDir)

        if ($Uninstall) {
            Uninstall-Skill -SkillSrc $skillDir -Target $target
        } else {
            Install-Skill -SkillSrc $skillDir -Target $target
        }
    }
}

Write-Host ""

if ($Uninstall) {
    Write-Host "Done! Skills uninstalled."
    exit 0
}

if ($SkipCli) {
    Write-Host "Note: -SkipCli is ignored (this repo does not install the ax CLI)"
}

Write-Host ""
if ($Copy) {
    Write-Host "Done! Skills copied into place."
} else {
    Write-Host "Done! Skills are ready to use."
    Write-Host "Keep this directory in place -- skills are symlinked here."
    Write-Host "To make standalone copies instead, re-run with -Copy."
}
