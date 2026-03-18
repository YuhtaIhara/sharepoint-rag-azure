# export-png.ps1
# draw.io ダイアグラムを個別 PNG にエクスポートするスクリプト
# 前提: draw.io Desktop がインストールされていること

$ErrorActionPreference = "Stop"

# draw.io 実行ファイルを探す
$drawioExe = $null
$candidates = @(
    "${env:ProgramFiles}\draw.io\draw.io.exe",
    "${env:LOCALAPPDATA}\Programs\draw.io\draw.io.exe",
    "${env:ProgramFiles(x86)}\draw.io\draw.io.exe"
)
foreach ($c in $candidates) {
    if (Test-Path $c) { $drawioExe = $c; break }
}
if (-not $drawioExe) {
    # Try to find via where command
    $drawioExe = (Get-Command draw.io -ErrorAction SilentlyContinue)?.Source
}
if (-not $drawioExe) {
    Write-Error "draw.io Desktop が見つかりません。インストールしてください: https://github.com/jgraph/drawio-desktop/releases"
    exit 1
}
Write-Host "draw.io found: $drawioExe" -ForegroundColor Green

# パス設定
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$inputFile = Join-Path $scriptDir "architecture.drawio"

if (-not (Test-Path $inputFile)) {
    Write-Error "入力ファイルが見つかりません: $inputFile"
    exit 1
}

# エクスポート設定
$exports = @(
    @{ PageIndex = 0; Output = "architecture-context.png" },
    @{ PageIndex = 1; Output = "architecture-container.png" },
    @{ PageIndex = 2; Output = "architecture-deployment.png" }
)

foreach ($export in $exports) {
    $outputFile = Join-Path $scriptDir $export.Output
    $pageIndex = $export.PageIndex

    Write-Host "Exporting page $pageIndex -> $($export.Output) ..." -ForegroundColor Cyan

    & $drawioExe `
        --export `
        --format png `
        --scale 2 `
        --border 10 `
        --page-index $pageIndex `
        --output $outputFile `
        $inputFile

    if ($LASTEXITCODE -ne 0) {
        Write-Warning "エクスポート失敗: page $pageIndex"
    } else {
        $size = (Get-Item $outputFile).Length
        Write-Host "  OK: $outputFile ($([math]::Round($size/1024))KB)" -ForegroundColor Green
    }
}

Write-Host "`nエクスポート完了!" -ForegroundColor Green
