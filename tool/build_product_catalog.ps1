param(
    [Parameter(Mandatory = $true)]
    [string]$SourceXlsx,

    [string]$OutputJson = ''
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression

function Get-CellText {
    param(
        [System.Xml.XmlElement]$Cell,
        [System.Collections.Generic.List[string]]$SharedStrings
    )

    $value = [string]$Cell.v
    if ([string]$Cell.t -eq 's' -and $value -ne '') {
        return $SharedStrings[[int]$value]
    }
    if ([string]$Cell.t -eq 'inlineStr') {
        return [string]$Cell.is.t
    }
    return $value
}

$resolvedSource = (Resolve-Path -LiteralPath $SourceXlsx).Path
if ($OutputJson -eq '') {
    $OutputJson = Join-Path $PSScriptRoot '..\assets\product_catalog.json'
}
$outputPath = [IO.Path]::GetFullPath($OutputJson)
$outputDirectory = Split-Path -Parent $outputPath
New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null

$stream = [IO.File]::Open(
    $resolvedSource,
    [IO.FileMode]::Open,
    [IO.FileAccess]::Read,
    [IO.FileShare]::ReadWrite
)
$archive = New-Object IO.Compression.ZipArchive(
    $stream,
    [IO.Compression.ZipArchiveMode]::Read,
    $false
)

try {
    $sharedStrings = New-Object 'System.Collections.Generic.List[string]'
    $sharedEntry = $archive.GetEntry('xl/sharedStrings.xml')
    if ($null -ne $sharedEntry) {
        $reader = New-Object IO.StreamReader($sharedEntry.Open())
        [xml]$sharedXml = $reader.ReadToEnd()
        $reader.Dispose()

        foreach ($item in $sharedXml.sst.si) {
            $builder = New-Object Text.StringBuilder
            if ($item.t) {
                [void]$builder.Append([string]$item.t)
            }
            if ($item.r) {
                foreach ($run in $item.r) {
                    [void]$builder.Append([string]$run.t)
                }
            }
            $sharedStrings.Add($builder.ToString())
        }
    }

    $sheetEntry = $archive.GetEntry('xl/worksheets/sheet1.xml')
    if ($null -eq $sheetEntry) {
        throw 'The first worksheet was not found in the XLSX file.'
    }

    $reader = New-Object IO.StreamReader($sheetEntry.Open())
    [xml]$sheetXml = $reader.ReadToEnd()
    $reader.Dispose()

    $unique = @{}
    $skippedRows = 0
    foreach ($row in $sheetXml.worksheet.sheetData.row | Select-Object -Skip 1) {
        $code = ''
        $name = ''
        foreach ($cell in $row.c) {
            $reference = [string]$cell.r
            if ($reference.StartsWith('A')) {
                $code = (Get-CellText $cell $sharedStrings).Trim().ToUpperInvariant()
            }
            elseif ($reference.StartsWith('B')) {
                $name = (Get-CellText $cell $sharedStrings).Trim()
            }
        }

        if ($code -eq '' -or $name -eq '') {
            $skippedRows++
            continue
        }

        $key = "$code`n$name"
        if (-not $unique.ContainsKey($key)) {
            $unique[$key] = [ordered]@{ code = $code; name = $name }
        }
    }

    $items = @($unique.Values | Sort-Object code, name)
    $sourceHash = (Get-FileHash -LiteralPath $resolvedSource -Algorithm SHA256).Hash
    $payload = [ordered]@{
        version = $sourceHash.Substring(0, 16)
        source = [IO.Path]::GetFileName($resolvedSource)
        items = $items
    }

    $json = $payload | ConvertTo-Json -Depth 4 -Compress
    [IO.File]::WriteAllText(
        $outputPath,
        $json,
        (New-Object Text.UTF8Encoding($false))
    )

    $ambiguous = @(
        $items |
            ForEach-Object { [pscustomobject]$_ } |
            Group-Object code |
            Where-Object Count -gt 1
    )
    Write-Host "Catalog written: $outputPath"
    Write-Host "Unique code/name pairs: $($items.Count)"
    Write-Host "Ambiguous barcode keys: $($ambiguous.Count)"
    Write-Host "Skipped empty rows: $skippedRows"
}
finally {
    $archive.Dispose()
    $stream.Dispose()
}
