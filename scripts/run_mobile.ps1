$ErrorActionPreference = 'Stop'
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
Push-Location (Join-Path $repoRoot 'apps/mobile')
try {
  flutter run --dart-define-from-file=(Join-Path $repoRoot '.env')
} finally {
  Pop-Location
}
