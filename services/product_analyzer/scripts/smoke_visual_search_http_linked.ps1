$ErrorActionPreference = 'Stop'
$serviceRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..\..')
$projectRef = (Get-Content (Join-Path $repoRoot 'supabase\.temp\project-ref') -Raw).Trim()
$keys = supabase projects api-keys --project-ref $projectRef -o json | ConvertFrom-Json
$serviceRole = $keys | Where-Object { $_.name -eq 'service_role' } | Select-Object -First 1
$anon = $keys | Where-Object { $_.name -eq 'anon' } | Select-Object -First 1
$env:SUPABASE_URL = "https://$projectRef.supabase.co"
$env:SUPABASE_SERVICE_ROLE_KEY = $serviceRole.api_key
$env:SUPABASE_ANON_KEY = $anon.api_key
Push-Location $serviceRoot
try {
    & '.\.venv\Scripts\python.exe' 'scripts\smoke_visual_search_http.py'
    exit $LASTEXITCODE
} finally {
    $env:SUPABASE_SERVICE_ROLE_KEY = $null
    $env:SUPABASE_ANON_KEY = $null
    Pop-Location
}
