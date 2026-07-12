param(
    [int]$Port = 8090
)

$ErrorActionPreference = 'Stop'
$serviceRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..\..')
$projectRefFile = Join-Path $repoRoot 'supabase\.temp\project-ref'
$python = Join-Path $serviceRoot '.venv\Scripts\python.exe'

if (-not (Test-Path $projectRefFile)) {
    throw 'Supabase project is not linked. Run: supabase link --project-ref <ref>'
}
if (-not (Test-Path $python)) {
    throw 'Analyzer virtual environment is missing.'
}

$projectRef = (Get-Content $projectRefFile -Raw).Trim()
$keys = supabase projects api-keys --project-ref $projectRef -o json |
    ConvertFrom-Json
$serviceRole = $keys |
    Where-Object { $_.name -eq 'service_role' } |
    Select-Object -First 1

if (-not $serviceRole.api_key) {
    throw 'Supabase CLI did not return a service-role key. Run: supabase login'
}

$env:SUPABASE_URL = "https://$projectRef.supabase.co"
$env:SUPABASE_SERVICE_ROLE_KEY = $serviceRole.api_key
$env:PORT = $Port.ToString()

Push-Location $serviceRoot
try {
    & $python -m uvicorn app.main:app --host 0.0.0.0 --port $Port
} finally {
    $env:SUPABASE_SERVICE_ROLE_KEY = $null
    Pop-Location
}
