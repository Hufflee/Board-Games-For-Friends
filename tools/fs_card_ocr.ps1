# Local Windows OCR for card text; input PNGs only, original assets stay unchanged.
param([string]$Folder = "build/fs_passive_audit/ocr_input", [int]$Limit = 0)
$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Runtime.WindowsRuntime
$null = [Windows.Storage.StorageFile, Windows.Storage, ContentType=WindowsRuntime]
$null = [Windows.Storage.Streams.IRandomAccessStream, Windows.Storage.Streams, ContentType=WindowsRuntime]
$null = [Windows.Graphics.Imaging.BitmapDecoder, Windows.Graphics.Imaging, ContentType=WindowsRuntime]
$null = [Windows.Graphics.Imaging.SoftwareBitmap, Windows.Graphics.Imaging, ContentType=WindowsRuntime]
$null = [Windows.Media.Ocr.OcrEngine, Windows.Foundation, ContentType=WindowsRuntime]
$null = [Windows.Globalization.Language, Windows.Globalization, ContentType=WindowsRuntime]
$asTask = [System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
    $_.Name -eq 'AsTask' -and $_.IsGenericMethod -and $_.GetParameters().Count -eq 1
} | Select-Object -First 1
function Await($Operation, $ResultType) {
    $task = $asTask.MakeGenericMethod($ResultType).Invoke($null, @($Operation))
    try { $task.Wait() } catch { throw $task.Exception.ToString() }
    return $task.Result
}
$language = New-Object Windows.Globalization.Language('ru')
$engine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromLanguage($language)
if ($null -eq $engine) { throw 'Russian OCR language is unavailable' }
$inputPath = (Resolve-Path -LiteralPath $Folder).Path
$outPath = Join-Path (Split-Path -Parent $inputPath) 'ocr'
[System.IO.Directory]::CreateDirectory($outPath) | Out-Null
$index = 0
foreach ($path in (Get-ChildItem -LiteralPath $inputPath -Filter '*.png' -File)) {
    $resultPath = Join-Path $outPath ($path.BaseName + '.json')
    if (Test-Path -LiteralPath $resultPath) { continue }
    $file = Await ([Windows.Storage.StorageFile]::GetFileFromPathAsync($path.FullName)) ([Windows.Storage.StorageFile])
    $stream = Await ($file.OpenAsync([Windows.Storage.FileAccessMode]::Read)) ([Windows.Storage.Streams.IRandomAccessStream])
    $decoder = Await ([Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($stream)) ([Windows.Graphics.Imaging.BitmapDecoder])
    $bitmap = Await ($decoder.GetSoftwareBitmapAsync()) ([Windows.Graphics.Imaging.SoftwareBitmap])
    $result = Await ($engine.RecognizeAsync($bitmap)) ([Windows.Media.Ocr.OcrResult])
    $lines = @($result.Lines | ForEach-Object { $_.Text })
    $data = @{ id = [int]$path.BaseName; text = $result.Text; lines = $lines }
    [System.IO.File]::WriteAllText($resultPath, ($data | ConvertTo-Json -Depth 5), [System.Text.UTF8Encoding]::new($false))
    $bitmap.Dispose()
    $stream.Dispose()
    $index += 1
    if ($index % 20 -eq 0) { Write-Output "OCR $index" }
    if ($Limit -gt 0 -and $index -ge $Limit) { break }
}
Write-Output "OCR DONE $index"
