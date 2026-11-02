param([string]$GamePath, [switch]$AllowRunning)
$ErrorActionPreference = 'Stop'
# Hash verification also runs on upgrades before other Utility cmdlets load.
Import-Module Microsoft.PowerShell.Utility -ErrorAction Stop
$package = $PSScriptRoot
$renamedPayload = Test-Path -LiteralPath "$package\BeyondApocalypse\Scripts\main.lua"
$payloadFolder = if ($renamedPayload) { 'BeyondApocalypse' } else { 'BasicM4' }
if (-not (Test-Path -LiteralPath "$package\$payloadFolder\Scripts\main.lua") -or -not (Test-Path -LiteralPath "$package\$payloadFolder\assets")) { throw 'The mod package is incomplete.' }
if (-not $GamePath) {
    $steam = (Get-ItemProperty 'HKCU:\Software\Valve\Steam' -ErrorAction SilentlyContinue).SteamPath
    $libraries = @($steam, "${env:ProgramFiles(x86)}\Steam") | Where-Object { $_ }
    if ($steam -and (Test-Path -LiteralPath "$steam\steamapps\libraryfolders.vdf")) {
        $content = Get-Content -LiteralPath "$steam\steamapps\libraryfolders.vdf" -Raw
        foreach ($match in [regex]::Matches($content, '"path"\s+"([^"]+)"')) {
            $libraries += $match.Groups[1].Value.Replace('\\', '\')
        }
    }
    $GamePath = $libraries | Select-Object -Unique | ForEach-Object { Join-Path $_ 'steamapps\common\Drive Beyond Horizons' } | Where-Object { Test-Path -LiteralPath (Join-Path $_ 'DriveBeyondHorizons\Binaries\Win64\DriveBeyondHorizons-Win64-Shipping.exe') } | Select-Object -First 1
}
if (-not $GamePath) { $GamePath = Read-Host 'Paste your Drive Beyond Horizons game folder' }
$GamePath = (Resolve-Path -LiteralPath $GamePath).Path
$bin = Join-Path $GamePath 'DriveBeyondHorizons\Binaries\Win64'
if (-not (Test-Path -LiteralPath "$bin\DriveBeyondHorizons-Win64-Shipping.exe")) { throw 'This is not the Drive Beyond Horizons game folder.' }
if ((Get-Process -Name 'DriveBeyondHorizons-Win64-Shipping' -ErrorAction SilentlyContinue) -and -not $AllowRunning) { throw 'Close Drive Beyond Horizons, then run Install again.' }
if (-not $renamedPayload -and (Test-Path -LiteralPath "$bin\ue4ss\Mods\BeyondApocalypse\Scripts\main.lua")) { throw 'Use the current Beyond Apocalypse package to update this renamed installation.' }
$loader = Join-Path $bin 'ue4ss'
$fresh = -not (Test-Path -LiteralPath "$loader\UE4SS.dll")
if ($fresh) {
    if (Test-Path -LiteralPath "$bin\dwmapi.dll") { throw 'An existing dwmapi.dll is present. Install the mod manually after checking your loader; it was not overwritten.' }
    $runtimeRoot = (Resolve-Path -LiteralPath "$package\runtime\ue4ss").Path
    New-Item -ItemType Directory -Path $loader -Force | Out-Null
    foreach ($file in Get-ChildItem -LiteralPath $runtimeRoot -Recurse -File) {
        $relative = $file.FullName.Substring($runtimeRoot.Length).TrimStart('\')
        $destination = [IO.Path]::GetFullPath((Join-Path $loader $relative))
        if (-not $destination.StartsWith([IO.Path]::GetFullPath($loader).TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Invalid loader file path.' }
        if (-not (Test-Path -LiteralPath $destination)) {
            New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
            Copy-Item -LiteralPath $file.FullName -Destination $destination
        }
    }
    Copy-Item -LiteralPath "$package\runtime\dwmapi.dll" -Destination $bin
} elseif ((Get-FileHash -LiteralPath "$loader\UE4SS.dll").Hash -ne (Get-FileHash -LiteralPath "$package\runtime\ue4ss\UE4SS.dll").Hash) {
    throw 'A different UE4SS build is already installed. It was left untouched. See README for manual installation and compatibility.'
}
$mods = Join-Path $loader 'Mods'
$target = [IO.Path]::GetFullPath((Join-Path $mods $payloadFolder))
$legacy = [IO.Path]::GetFullPath((Join-Path $mods 'BasicM4'))
$managedRoot = [IO.Path]::GetFullPath($mods).TrimEnd('\') + '\'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
$backup = [IO.Path]::GetFullPath((Join-Path $bin "BeyondApocalypse-backups\$stamp"))
$archiveRoot = [IO.Path]::GetFullPath((Join-Path $bin 'BeyondApocalypse-backups')).TrimEnd('\') + '\'
if (-not $backup.StartsWith($archiveRoot, [StringComparison]::OrdinalIgnoreCase)) { throw 'Invalid backup path.' }
foreach ($path in @($target, $legacy)) {
    if (-not $path.StartsWith($managedRoot, [StringComparison]::OrdinalIgnoreCase)) { throw 'Invalid mod path.' }
    if (Test-Path -LiteralPath $path) {
        if ((Get-Item -LiteralPath $path).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'A linked mod folder was left untouched.' }
        if (Get-ChildItem -LiteralPath $path -Recurse -Force | Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint } | Select-Object -First 1) { throw 'A linked mod file was left untouched.' }
    }
}
if ($renamedPayload -and (Test-Path -LiteralPath $legacy)) {
    New-Item -ItemType Directory -Path $backup -Force | Out-Null
    if (-not (Test-Path -LiteralPath $target)) {
        Copy-Item -LiteralPath $legacy -Destination (Join-Path $backup 'legacy-before-migration') -Recurse
        Move-Item -LiteralPath $legacy -Destination $target
    } else {
        # ZIP upgrades may already have the new folder. Canonical data wins;
        # retain every legacy original in the backup and fill only absent files.
        foreach ($file in Get-ChildItem -LiteralPath $legacy -Recurse -File -Force) {
            $relative = $file.FullName.Substring($legacy.Length).TrimStart('\')
            $destination = [IO.Path]::GetFullPath((Join-Path $target $relative))
            if (-not $destination.StartsWith($target + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Invalid migrated file path.' }
            if (-not (Test-Path -LiteralPath $destination)) {
                New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
                Copy-Item -LiteralPath $file.FullName -Destination $destination
            }
        }
        Move-Item -LiteralPath $legacy -Destination (Join-Path $backup 'legacy-before-migration')
    }
}
$existingConfig = if (Test-Path -LiteralPath "$target\Scripts\config.lua") { [IO.File]::ReadAllBytes("$target\Scripts\config.lua") } else { $null }
if (Test-Path -LiteralPath $target) {
    if (-not $backup.StartsWith($archiveRoot, [StringComparison]::OrdinalIgnoreCase)) { throw 'Backup path escaped the archive.' }
    New-Item -ItemType Directory -Path $backup -Force | Out-Null
    Copy-Item -LiteralPath $target -Destination $backup -Recurse
}
New-Item -ItemType Directory -Path $target, "$target\state" -Force | Out-Null
foreach ($name in @('Scripts', 'assets')) {
    # Replace only this mod's managed content, so obsolete 0.2 files disappear.
    $contentPath = [IO.Path]::GetFullPath((Join-Path $target $name))
    $targetRoot = [IO.Path]::GetFullPath($target).TrimEnd('\') + '\'
    if (-not $contentPath.StartsWith($targetRoot, [StringComparison]::OrdinalIgnoreCase)) { throw 'Content path escaped the mod folder.' }
    if (Test-Path -LiteralPath $contentPath) {
        if ((Get-Item -LiteralPath $contentPath).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Refusing to replace a linked content folder.' }
        $retiredContent = Join-Path $backup 'retired-managed'
        $retiredDestination = [IO.Path]::GetFullPath((Join-Path $retiredContent $name))
        if (-not $retiredDestination.StartsWith($backup + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Retired content escaped the backup.' }
        New-Item -ItemType Directory -Path $retiredContent -Force | Out-Null
        Move-Item -LiteralPath $contentPath -Destination $retiredDestination
    }
    Copy-Item -LiteralPath "$package\$payloadFolder\$name" -Destination $target -Recurse -Force
}
# The previous mod backup above contains any retired attachment ownership data.
if ($null -ne $existingConfig) { [IO.File]::WriteAllBytes("$target\Scripts\config.lua", $existingConfig) }
foreach ($retired in @('attachments.txt', 'attachments.txt.bak', 'attachments.txt.tmp')) {
    $retiredPath = Join-Path $target "state\$retired"
    if (Test-Path -LiteralPath $retiredPath) {
        $retiredState = Join-Path $backup 'retired-state'
        New-Item -ItemType Directory -Path $retiredState -Force | Out-Null
        Move-Item -LiteralPath $retiredPath -Destination (Join-Path $retiredState $retired)
    }
}
# Do not overwrite the host's conversion registry during updates.
$list = Join-Path $mods 'mods.txt'
$lines = if (Test-Path -LiteralPath $list) { @(Get-Content -LiteralPath $list) } else { @() }
$lines = @($lines | Where-Object { $_ -notmatch '^\s*(BasicM4|BeyondApocalypse)\s*:' })
$lines += "$payloadFolder : 1"
$lines | Set-Content -LiteralPath $list -Encoding ascii
# The old launcher reads this inert version shim; it never starts a second mod.
if ($renamedPayload) {
    New-Item -ItemType Directory -Path "$legacy\Scripts" -Force | Out-Null
    foreach ($name in @('main.lua','release.lua')) { Copy-Item -LiteralPath "$package\BasicM4\Scripts\$name" -Destination "$legacy\Scripts\$name" -Force }
}
$releaseText = Get-Content -LiteralPath "$target\Scripts\release.lua" -Raw
$releaseVersion = [regex]::Match($releaseText, "Version='([^']+)'").Groups[1].Value
$releaseChannel = [regex]::Match($releaseText, "Channel='([^']+)'").Groups[1].Value
"Beyond Apocolypse $releaseVersion $releaseChannel installed. Existing mod state and configuration retained. See README.txt and BACKPACKS.md for compatibility, controls and test limits." | Write-Host

# Retired local diagnostics: remove only their two exact output filenames.
foreach ($diagnosticRoot in @($GamePath, $target)) {
    foreach ($diagnosticName in @('SENDTOROOK.txt', 'SENDTOROOK-previous.txt')) {
        $diagnosticFile = Join-Path $diagnosticRoot $diagnosticName
        if (Test-Path -LiteralPath $diagnosticFile -PathType Leaf) { Remove-Item -LiteralPath $diagnosticFile }
    }
}
