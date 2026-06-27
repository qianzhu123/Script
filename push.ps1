
$src = "D:\code\myweb\daily"
$git = "D:\tools\Productivity\AI_Tools\AI\Cherry-studio\Cherry Studio\codemywebdaily"

Copy-Item "$src\server.js" "$git\server.js" -Force
if (!(Test-Path "$git\public")) { New-Item -ItemType Directory -Path "$git\public" | Out-Null }
Copy-Item "$src\public\app.js"     "$git\public\app.js"     -Force
Copy-Item "$src\public\index.html" "$git\public\index.html" -Force
Copy-Item "$src\public\style.css"  "$git\public\style.css"  -Force

Set-Location $git

git add server.js public/app.js public/index.html public/style.css
git commit -m "fix: bat execution, tab compression, stdin input"
git push origin main --force

Write-Host "Done."
