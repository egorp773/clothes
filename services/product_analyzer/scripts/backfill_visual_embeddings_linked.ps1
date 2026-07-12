param(
    [int]$BatchSize = 100,
    [string[]]$ProductId = @()
)

$ErrorActionPreference = 'Stop'
$serviceRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..\..')
$projectRefFile = Join-Path $repoRoot 'supabase\.temp\project-ref'
$python = Join-Path $serviceRoot '.venv\Scripts\python.exe'

if (-not (Test-Path $projectRefFile)) {
    throw 'Supabase project is not linked.'
}

$projectRef = (Get-Content $projectRefFile -Raw).Trim()
$keys = supabase projects api-keys --project-ref $projectRef -o json |
    ConvertFrom-Json
$serviceRole = $keys |
    Where-Object { $_.name -eq 'service_role' } |
    Select-Object -First 1
if (-not $serviceRole.api_key) {
    throw 'Supabase CLI did not return a service-role key.'
}

$env:SUPABASE_URL = "https://$projectRef.supabase.co"
$env:SUPABASE_SERVICE_ROLE_KEY = $serviceRole.api_key
Push-Location $serviceRoot
try {
    $arguments = @('scripts\backfill_visual_embeddings.py', '--batch-size', $BatchSize)
    foreach ($id in $ProductId) {
        $arguments += @('--product-id', $id)
    }
    & $python @arguments
    exit $LASTEXITCODE
} finally {
    $env:SUPABASE_SERVICE_ROLE_KEY = $null
    Pop-Location
}
