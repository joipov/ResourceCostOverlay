# Builds a CurseForge/Wago zip in .release/. The addon folder is the zip root.
# Dev files and assets/ are left out. assets/ stays in git.
$ErrorActionPreference = "Stop"
$root = $PSScriptRoot
if (-not $root) { $root = Split-Path -Parent $MyInvocation.MyCommand.Path }
$name = Split-Path -Leaf $root
$tocPath = Join-Path $root ($name + ".toc")
$toc = Get-Content -LiteralPath $tocPath -Raw
$match = [regex]::Match($toc, '(?m)^## Version:\s*(\S+)')
if (-not $match.Success) { throw "Version not found in $tocPath" }
$version = $match.Groups[1].Value

$releaseDir = Join-Path $root ".release"
New-Item -ItemType Directory -Force -Path $releaseDir | Out-Null
$zipPath = Join-Path $releaseDir ($name + "-" + $version + ".zip")
if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }

$skipNames = @{
	"assets" = $true
	"tests" = $true
	"CODE_AUDIT.md" = $true
	"package.ps1" = $true
}

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

function Add-Tree($archive, [string]$from, [string]$prefix) {
	Get-ChildItem -Force -LiteralPath $from | ForEach-Object {
		if ($_.Name.StartsWith(".")) { return }
		if ($skipNames.ContainsKey($_.Name)) { return }
		$rel = $prefix + "/" + $_.Name
		if ($_.PSIsContainer) {
			Add-Tree $archive $_.FullName $rel
		} else {
			$entry = $archive.CreateEntry($rel, [System.IO.Compression.CompressionLevel]::Optimal)
			$inStream = [System.IO.File]::OpenRead($_.FullName)
			try {
				$outStream = $entry.Open()
				try { $inStream.CopyTo($outStream) } finally { $outStream.Dispose() }
			} finally { $inStream.Dispose() }
		}
	}
}

$archive = [System.IO.Compression.ZipFile]::Open($zipPath, [System.IO.Compression.ZipArchiveMode]::Create)
try {
	Add-Tree $archive $root $name
} finally {
	$archive.Dispose()
}
Write-Output $zipPath
