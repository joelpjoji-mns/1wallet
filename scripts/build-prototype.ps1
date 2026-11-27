param()

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Push-Location $root
try {
    flutter build web --release --no-wasm-dry-run --no-web-resources-cdn --base-href /app/ --target lib\src\app\prototype_main.dart --output build\prototype\app
    if ($LASTEXITCODE -ne 0) {
        throw "Prototype web build failed with exit code $LASTEXITCODE."
    }
    # The prototype never loads environment configuration; do not serve it.
    $configAsset = Join-Path $root 'build\prototype\app\assets\config.env'
    if (Test-Path $configAsset) {
        Remove-Item -LiteralPath $configAsset
    }
    Copy-Item -LiteralPath (Join-Path $root 'web\prototype\index.html') -Destination (Join-Path $root 'build\prototype\index.html')
    Copy-Item -LiteralPath (Join-Path $root 'web\prototype\studio.js') -Destination (Join-Path $root 'build\prototype\studio.js')
    Write-Host 'Prototype built. Serve build\prototype on localhost, then open the server URL in a browser.'
} finally {
    Pop-Location
}
