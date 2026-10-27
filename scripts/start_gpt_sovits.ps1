[CmdletBinding()]
param(
    [switch]$ResolveOnly,
    [string]$AppDirectory,
    [string]$WorkingDirectory = (Get-Location).Path,
    [string[]]$DriveRoots = @(
        [System.IO.DriveInfo]::GetDrives() |
            Where-Object { $_.IsReady -and $_.DriveType -in @('Fixed', 'Removable') } |
            ForEach-Object { $_.RootDirectory.FullName } |
            Sort-Object
    ),
    [string]$RootOverride = $env:GPT_SOVITS_ROOT
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
if ([string]::IsNullOrWhiteSpace($AppDirectory)) {
    $AppDirectory = Split-Path -Parent $PSScriptRoot
}

function Test-SovitsInstallation([string]$Candidate) {
    return (
        [IO.File]::Exists([IO.Path]::Combine($Candidate, 'api_v2.py')) -and
        [IO.File]::Exists([IO.Path]::Combine($Candidate, 'runtime\python.exe')) -and
        [IO.File]::Exists([IO.Path]::Combine($Candidate, 'GPT_SoVITS\configs\tts_infer.yaml'))
    )
}

function Resolve-SovitsPath([string]$Base, [string]$Value) {
    $valuePath = $Value.Trim().Trim([char]0xFEFF).Trim('"')
    if ([string]::IsNullOrWhiteSpace($valuePath)) { return $null }
    if (-not [IO.Path]::IsPathRooted($valuePath)) {
        $valuePath = [IO.Path]::Combine($Base, $valuePath)
    }
    return [IO.Path]::GetFullPath($valuePath)
}

function Find-SovitsRoot {
    if (-not [string]::IsNullOrWhiteSpace($RootOverride)) {
        $candidate = Resolve-SovitsPath $AppDirectory $RootOverride
        if ($candidate -and (Test-SovitsInstallation $candidate)) { return $candidate }
    }

    # Keep the same priority as lib/gpt_sovits_paths.dart: executable, then cwd.
    $bases = [Collections.Generic.List[string]]::new()
    foreach ($start in @($AppDirectory, $WorkingDirectory)) {
        $directory = [IO.DirectoryInfo]::new($start)
        while ($null -ne $directory.Parent) {
            if (-not $bases.Contains($directory.FullName)) { $bases.Add($directory.FullName) }
            $directory = $directory.Parent
        }
    }

    foreach ($base in $bases) {
        $pathFile = [IO.Path]::Combine($base, 'gpt_sovits_path.txt')
        try {
            if (-not [IO.File]::Exists($pathFile)) { continue }
            $candidate = Resolve-SovitsPath $base ([IO.File]::ReadAllText($pathFile))
            if ($candidate -and (Test-SovitsInstallation $candidate)) { return $candidate }
        } catch { continue }
    }

    foreach ($base in @($bases.ToArray()) + @($DriveRoots)) {
        if (Test-SovitsInstallation $base) { return $base }
        $candidate = [IO.Path]::Combine($base, 'GPT-SoVITS')
        if (Test-SovitsInstallation $candidate) { return $candidate }
        try {
            $children = [IO.Directory]::GetDirectories($base) |
                Where-Object { [IO.Path]::GetFileName($_) -match '^GPT-SoVITS(?:-|$)' } |
                Sort-Object
            foreach ($candidate in $children) {
                if (Test-SovitsInstallation $candidate) { return $candidate }
            }
        } catch { continue }
    }
    return $null
}

$sovitsRoot = Find-SovitsRoot
if (-not $sovitsRoot) {
    throw 'GPT-SoVITS not found. Place it near the app or at a drive root, or set gpt_sovits_path.txt / GPT_SOVITS_ROOT.'
}
if ($ResolveOnly) {
    Write-Output $sovitsRoot
    exit 0
}

Write-Host "Starting GPT-SoVITS API (port 9880): $sovitsRoot"
Push-Location -LiteralPath $sovitsRoot
try {
    & ([IO.Path]::Combine($sovitsRoot, 'runtime\python.exe')) api_v2.py -c GPT_SoVITS/configs/tts_infer.yaml
    $sovitsExitCode = $LASTEXITCODE
} finally {
    Pop-Location
}
exit $sovitsExitCode
