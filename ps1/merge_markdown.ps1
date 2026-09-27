# Merge Markdown Documents
#
# Merges one or more Markdown documents or folders (each containing Markdown
# files plus image files) into a single output folder in the following layout:
#
#     <target>/
#         README.md        # all source Markdown content concatenated in order
#         assets/          # every local relative-path image is copied here
#
# Image path rewriting rules:
#   - Local images referenced by a relative path are copied into assets/ and
#     the Markdown link is rewritten to "assets/<filename>". The original file
#     name is preserved (no renaming).
#   - Remote links (http://, https://) are left untouched.
#   - Absolute local paths (e.g. C:\images\a.png) are left untouched.
#   - Other Markdown links (URLs, anchors) are left untouched.
#
# Input method (double-click friendly):
#   Run the script. It prompts for source paths, one per line. Enter an empty
#   line to finish the source list, then enter the target merge folder path.
#   Accepted separators between source paths: newline (one per line), comma,
#   semicolon, or whitespace. A line is parsed by splitting on these
#   separators, so multiple paths on one line are also accepted.
#
# Sources can be:
#   - A single .md file
#   - A folder: every .md file directly inside it is a source document; every
#     image file directly inside it is collected as an image asset.
#
#   The merge order follows the order in which sources are entered. For a
#     folder source, its .md files are sorted by name before being appended.

$ErrorActionPreference = "Stop"

function Get-SourcePaths {
    Write-Host ""
    Write-Host "Enter source Markdown files or folders."
    Write-Host "Absolute paths (C:\, D:\, ...) start a new path automatically."
    Write-Host "Wrap relative paths in double quotes and separate with a delimiter."
    $line = Read-Host "Source paths"
    $paths = @()
    if (-not [string]::IsNullOrWhiteSpace($line)) {
        $paths = @(Split-PathTokens $line)
    }
    return $paths
}

function Split-PathTokens {
    param([string]$Line)
    <#
        Split an input line into Windows path tokens.

        Two input shapes are supported:

        1. Absolute paths starting with a drive letter + ':' (e.g. C:\, D:\).
           Each drive-letter colon marks the START of a new path. Everything
           between one drive start and the next is one path, so an absolute
           path may contain spaces, dots, Chinese characters, commas, and
           semicolons. The user may wrap such paths in double quotes (the
           quotes are optional and are stripped).

        2. Relative paths (no drive letter). These MUST be wrapped in double
           quotes; multiple quoted relative paths are separated by a comma,
           semicolon, or whitespace between the quoted segments.

        The parser first strips double quotes, then scans the resulting text
        for drive-letter boundaries. Quoted segments are kept whole; the
        tokens between quoted segments are split on comma/semicolon/whitespace
        AND on drive-colon boundaries.
    #>
    # Step 1: strip every double quote, but remember the character offsets so
    # we can also break tokens at the seams between two quoted segments.
    $stripped = New-Object System.Text.StringBuilder
    $seams = New-Object System.Collections.Generic.List[int]
    $inQuotes = $false
    for ($i = 0; $i -lt $Line.Length; $i++) {
        $ch = $Line[$i]
        if ($ch -eq '"') {
            if ($inQuotes) {
                $inQuotes = $false
                if ($stripped.Length -gt 0) { $seams.Add($stripped.Length) }
            } else {
                $inQuotes = $true
                if ($stripped.Length -gt 0) { $seams.Add($stripped.Length) }
            }
        } else {
            [void]$stripped.Append($ch)
        }
    }
    $text = $stripped.ToString()

    if ([string]::IsNullOrWhiteSpace($text)) { return @() }

    # Build a regex alternation of all "hard break" positions: any
    # comma/semicolon/whitespace run, plus the seam offsets we recorded.
    $hasSeams = $seams.Count -gt 0

    $tokens = @()
    $current = New-Object System.Text.StringBuilder
    for ($i = 0; $i -lt $text.Length; $i++) {
        $ch = $text[$i]

        # Is this position a "hard break" (seam between two quoted segments)?
        $atSeam = $false
        if (-not $inQuotes) {
            foreach ($s in $seams) { if ($s -eq $i) { $atSeam = $true; break } }
        }

        # Is this the start of a drive letter (letter + ':')?
        $isDriveStart = $false
        if (($i + 1) -lt $text.Length -and $text[$i + 1] -eq ':') {
            $upper = [char]::ToUpper($ch)
            if ($upper -ge 'A' -and $upper -le 'Z') { $isDriveStart = $true }
        }

        if ($atSeam -and $current.Length -gt 0) {
            $t = $current.ToString().Trim(' ', "`t", ',', ';')
            if ($t -ne "") { $tokens += $t }
            [void]$current.Clear()
        }

        if ($isDriveStart -and $current.Length -gt 0) {
            $t = $current.ToString().Trim(' ', "`t", ',', ';')
            if ($t -ne "") { $tokens += $t }
            [void]$current.Clear()
        }

        [void]$current.Append($ch)
    }
    if ($current.Length -gt 0) {
        $t = $current.ToString().Trim(' ', "`t", ',', ';')
        if ($t -ne "") { $tokens += $t }
    }
    return ($tokens | Where-Object { $_ -ne "" })
}

function Get-TargetPath {
    Write-Host ""
    Write-Host "Enter the output folder path (will be created if missing)."
    Write-Host "Wrap the path in double quotes if it contains spaces."
    $target = Read-Host "Output path"
    if ([string]::IsNullOrWhiteSpace($target)) {
        throw "No output folder was provided."
    }
    $target = $target.Trim()
    if ($target.Length -ge 2 -and $target.StartsWith('"') -and $target.EndsWith('"')) {
        $target = $target.Substring(1, $target.Length - 2)
    }
    return $target
}

function Test-IsImageFile {
    param([string]$Path)
    $imageExtensions = @(
        ".png", ".jpg", ".jpeg", ".gif", ".bmp", ".webp",
        ".svg", ".ico", ".tif", ".tiff"
    )
    $ext = [System.IO.Path]::GetExtension($Path)
    return $imageExtensions -contains $ext.ToLower()
}

function Get-ImageBaseName {
    param([string]$Path)
    return [System.IO.Path]::GetFileName($Path)
}

function Test-IsMarkdownFile {
    param([string]$Path)
    $ext = [System.IO.Path]::GetExtension($Path)
    return $ext.ToLower() -eq ".md"
}

function Test-IsRemoteOrAbsolute {
    param([string]$Url)
    if ($Url -match '^[a-zA-Z][a-zA-Z0-9+.\-]*://') { return $true }   # remote URL
    if ($Url -match '^[A-Za-z]:[\\/]' -or $Url -match '^\\\\') { return $true } # Windows absolute / UNC
    if ($Url -match '^/') { return $true }                              # POSIX absolute
    if ($Url.StartsWith("#")) { return $true }                          # anchor
    if ($Url.StartsWith("mailto:", [StringComparison]::OrdinalIgnoreCase)) { return $true }
    if ($Url -match '^data:') { return $true }
    return $false
}

# Regex group names:
#   alt   -> alt text
#   src   -> image path
#   title -> optional title text
$ImagePattern = '(?ms)!\[(?<alt>[^\]]*)\]\(\s*(?<src>.*?)\s*(?:\s(?<!\\)"(?<title>[^"]*)")?\)'

function Resolve-RelativeImage {
    param(
        [string]$SourceFile,
        [string]$Src
    )
    <#
        Resolve a relative image reference from a Markdown source file.
        Returns the full local image path if the file exists, otherwise $null.
        Anchor and same-folder relative paths are resolved against the source
        file directory; assets/... paths are resolved against the source file
        directory (handles the common assets/ convention).
    #>
    if ($Src.StartsWith("#")) { return $null }
    $decoded = $Src -replace '%20', ' '
    if ($decoded -match '^[A-Za-z]:[\\/]' -or $decoded -match '^\\\\' -or $decoded -match '^/') {
        $candidate = $decoded
    } elseif ($decoded -match '^[a-zA-Z][a-zA-Z0-9+.\-]*://') {
        return $null
    } else {
        $baseDir = Split-Path -Parent $SourceFile
        $candidate = Join-Path $baseDir $decoded
    }
    if (Test-Path -LiteralPath $candidate -PathType Leaf) {
        return (Get-Item -LiteralPath $candidate).FullName
    }
    return $null
}

function MergeDocuments {
    param(
        [string[]]$Sources,
        [string]$Target
    )

    if ($Sources.Count -eq 0) {
        throw "No source paths were provided."
    }

    $targetFull = (Resolve-Path -LiteralPath ($Target.TrimEnd('\/')) -ErrorAction SilentlyContinue)
    if (-not $targetFull) {
        New-Item -ItemType Directory -Path $Target -Force | Out-Null
        $targetFull = (Get-Item -LiteralPath $Target).FullName
    } else {
        $targetFull = $targetFull.Path
    }

    $assetsDir = Join-Path $targetFull "assets"
    New-Item -ItemType Directory -Path $assetsDir -Force | Out-Null

    # First pass: collect an ordered list of source markdown files and the
    # set of folder-level image files available as assets.
    $mdFiles = @()          # ordered list of full paths to source .md files
    $extraImagePool = @{}   # fullPath -> $true, from folder sources

    foreach ($src in $Sources) {
        if (-not (Test-Path -LiteralPath $src)) {
            Write-Warning "Source not found, skipped: $src"
            continue
        }
        $item = Get-Item -LiteralPath $src
        if ($item.PSIsContainer) {
            $children = Get-ChildItem -LiteralPath $item.FullName -File | Sort-Object Name
            foreach ($ch in $children) {
                if (Test-IsMarkdownFile $ch.FullName) {
                    $mdFiles += $ch.FullName
                } elseif (Test-IsImageFile $ch.FullName) {
                    $extraImagePool[$ch.FullName] = $true
                }
            }
        } else {
            if (Test-IsMarkdownFile $item.FullName) {
                $mdFiles += $item.FullName
            } elseif (Test-IsImageFile $item.FullName) {
                $extraImagePool[$item.FullName] = $true
            } else {
                Write-Warning "Unsupported file type, skipped: $($item.FullName)"
            }
        }
    }

    if ($mdFiles.Count -eq 0) {
        throw "No Markdown source files were found among the provided paths."
    }

    # Track which asset filenames have been written to avoid collisions while
    # preserving names. On a name clash, a numeric suffix is appended.
    $usedAssetNames = @{}
    $pendingCopies = @{}  # sourceFull -> destFileName

    function Get-UniqueAssetName {
        param([string]$OriginalName)
        if (-not $usedAssetNames.ContainsKey($OriginalName)) {
            $usedAssetNames[$OriginalName] = $true
            return $OriginalName
        }
        $base = [System.IO.Path]::GetFileNameWithoutExtension($OriginalName)
        $ext = [System.IO.Path]::GetExtension($OriginalName)
        $i = 1
        while ($true) {
            $candidate = "${base}_${i}${ext}"
            if (-not $usedAssetNames.ContainsKey($candidate)) {
                $usedAssetNames[$candidate] = $true
                return $candidate
            }
            $i++
        }
    }

    $builder = New-Object System.Text.StringBuilder
    $firstDoc = $true

    foreach ($md in $mdFiles) {
        Write-Host "Processing: $md"
        $content = Get-Content -LiteralPath $md -Raw -Encoding UTF8

        $rewritten = [regex]::Replace($content, $ImagePattern, {
            param($m)
            $alt = $m.Groups['alt'].Value
            $src = $m.Groups['src'].Value
            $title = $m.Groups['title'].Value

            if (Test-IsRemoteOrAbsolute $src) {
                return $m.Value
            }

            $imagePath = Resolve-RelativeImage -SourceFile $md -Src $src
            if (-not $imagePath) {
                return $m.Value
            }

            $originalName = Get-ImageBaseName $imagePath
            if ($pendingCopies.ContainsKey($imagePath)) {
                $assetName = $pendingCopies[$imagePath]
            } else {
                $assetName = Get-UniqueAssetName $originalName
                $pendingCopies[$imagePath] = $assetName
            }

            if ($title) {
                return "[$alt](assets/$assetName `"$title`")"
            } else {
                return "[$alt](assets/$assetName)"
            }
        })

        if ($firstDoc) {
            [void]$builder.Append($rewritten)
            $firstDoc = $false
        } else {
            [void]$builder.AppendLine()
            [void]$builder.AppendLine()
            [void]$builder.Append($rewritten)
        }
    }

    # Second pass: copy every image referenced by a rewritten markdown file
    # into assets/. Then copy any folder-level images that were never
    # referenced (their names are still preserved).
    foreach ($imagePath in $pendingCopies.Keys) {
        $assetName = $pendingCopies[$imagePath]
        $dest = Join-Path $assetsDir $assetName
        if (Test-Path -LiteralPath $imagePath) {
            Copy-Item -LiteralPath $imagePath -Destination $dest -Force
            Write-Host "Copied image: $assetName"
        } else {
            Write-Warning "Image file missing, skipped: $imagePath"
        }
    }

    foreach ($imagePath in $extraImagePool.Keys) {
        $originalName = Get-ImageBaseName $imagePath
        if ($usedAssetNames.ContainsKey($originalName)) {
            $assetName = Get-UniqueAssetName $originalName
        } else {
            $assetName = $originalName
            $usedAssetNames[$originalName] = $true
        }
        $dest = Join-Path $assetsDir $assetName
        Copy-Item -LiteralPath $imagePath -Destination $dest -Force
        Write-Host "Copied extra image: $assetName"
    }

    $readmePath = Join-Path $targetFull "README.md"
    [System.IO.File]::WriteAllText($readmePath, $builder.ToString(), (New-Object System.Text.UTF8Encoding($false)))

    Write-Host ""
    Write-Host "Merge complete."
    Write-Host "  Target : $targetFull"
    Write-Host "  Output : README.md"
    Write-Host "  Images : $($pendingCopies.Count) referenced + $($extraImagePool.Count) extra written to assets/"
}

function Main {
    Write-Host "===== Merge Markdown Documents ====="

    $sources = Get-SourcePaths
    if ($sources.Count -eq 0) {
        Write-Warning "No source paths were entered."
        return
    }
    $target = Get-TargetPath

    try {
        MergeDocuments -Sources $sources -Target $target
    } catch {
        Write-Host ""
        Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# Run only when launched directly, not when dot-sourced.
if ($MyInvocation.InvocationName -ne '.') { Main }
