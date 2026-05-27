$ErrorActionPreference = 'Stop'
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
Push-Location (Join-Path $repoRoot 'apps/web_desktop')
try {
  flutter run -d chrome --dart-define-from-file=(Join-Path $repoRoot '.env')
} finally {
  Pop-Location
}
