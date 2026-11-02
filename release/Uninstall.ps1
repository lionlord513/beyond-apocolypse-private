param([Parameter(Mandatory=$true)][string]$GamePath)
$ErrorActionPreference = 'Stop'
$bin = Join-Path (Resolve-Path -LiteralPath $GamePath).Path 'DriveBeyondHorizons\Binaries\Win64'
if (-not (Test-Path -LiteralPath "$bin\DriveBeyondHorizons-Win64-Shipping.exe")) { throw 'Incorrect game folder.' }
if (Get-Process -Name 'DriveBeyondHorizons-Win64-Shipping' -ErrorAction SilentlyContinue) { throw 'Close the game first.' }
$list = Join-Path $bin 'ue4ss\Mods\mods.txt'
$lines = @(if (Test-Path -LiteralPath $list) { Get-Content -LiteralPath $list }) | ForEach-Object { if ($_ -match '^\s*(?:BasicM4|BeyondApocalypse)\s*:') { ($_ -replace ':.*$', ': 0') } else { $_ } }
$lines | Set-Content -LiteralPath $list -Encoding ascii
foreach ($modFolder in @('BeyondApocalypse','BasicM4')) {
$marker = Join-Path $bin "ue4ss\Mods\$modFolder\enabled.txt"
if (Test-Path -LiteralPath $marker) { Remove-Item -LiteralPath $marker }
$target=[IO.Path]::GetFullPath((Join-Path $bin "ue4ss\Mods\$modFolder"))
$managedRoot=[IO.Path]::GetFullPath((Join-Path $bin 'ue4ss\Mods')).TrimEnd('\')+'\'
if (-not $target.StartsWith($managedRoot,[StringComparison]::OrdinalIgnoreCase)) { throw 'Invalid mod path.' }
$backup=[IO.Path]::GetFullPath((Join-Path $bin ('BeyondApocalypse-backups\uninstalled-'+$modFolder+'-'+(Get-Date -Format 'yyyyMMdd-HHmmss-fff'))))
$archiveRoot=[IO.Path]::GetFullPath((Join-Path $bin 'BeyondApocalypse-backups')).TrimEnd('\')+'\'
if (-not $backup.StartsWith($archiveRoot,[StringComparison]::OrdinalIgnoreCase)) { throw 'Invalid backup path.' }
New-Item -ItemType Directory -Path $backup -Force | Out-Null
$configuration=Join-Path $target 'Scripts\config.lua'
$settings=if(Test-Path -LiteralPath $configuration){[IO.File]::ReadAllBytes($configuration)}else{$null}
foreach($name in @('Scripts','assets')) {
 $path=[IO.Path]::GetFullPath((Join-Path $target $name))
 if (-not $path.StartsWith($target+'\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Invalid content path.' }
 if(Test-Path -LiteralPath $path) {
  if((Get-Item -LiteralPath $path).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Linked mod folder was left untouched.'}
  Move-Item -LiteralPath $path -Destination (Join-Path $backup $name)
 }
}
if($null -ne $settings){New-Item -ItemType Directory -Path (Join-Path $target 'Scripts') -Force | Out-Null;[IO.File]::WriteAllBytes($configuration,$settings)}
}
Write-Host 'Mod uninstalled. Saves, settings, item records and other mods were kept.'
