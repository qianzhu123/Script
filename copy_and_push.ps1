$src = "D:\code\myweb\daily"
$dst = "D:\tools\Productivity\AI_Tools\AI\Cherry-studio\Cherry Studio\codemywebdaily"

# create public Directory
$pubDst = $dst + "\public"
if (-not (Test-Path $pubDst)) {
 New-Item -ItemType Directory -Path $pubDst | Out-Null
}

# copy file
$maps = @(
 ("server.js", "server.js"),
 ("public\app.js", "public\app.js"),
 ("public\index.html", "public\index.html"),
 ("public\style.css", "public\style.css")
)

foreach ($m in $maps) {
 $from = $src + "\" + $m[0]
 $to = $dst + "\" + $m[1]
 Copy-Item -LiteralPath $from -Destination $to -Force
 Write-Host "Copied: $($m[0])"
}

# git add + commit + push
Set-Location $dst
git add server.js public/app.js public/index.html public/style.css
git commit -m "fix: chcp utf8 shell mode and tab/input improvements"
git push origin main
Write-Host "Push done."
