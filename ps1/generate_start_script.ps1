param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$InputArgs
)

$ErrorActionPreference = 'Stop'

function Info($m) { Write-Host "[INFO] $m" }
function Warn($m) { Write-Host "[WARN] $m" }
function Err($m)  { Write-Host "[ERROR] $m" }

function Get-ProjectRoot([string]$PathText) {
    $p = $PathText.Trim().Trim('"')
    if (-not $p) { throw 'Empty path.' }
    if (-not (Test-Path -LiteralPath $p)) { throw "Path does not exist: $p" }
    $item = Get-Item -LiteralPath $p
    if ($item.PSIsContainer) { return $item.FullName.TrimEnd('\') }
    return $item.Directory.FullName.TrimEnd('\')
}

function Get-FirstFile($Root, [string[]]$Patterns) {
    foreach ($pattern in $Patterns) {
        $f = Get-ChildItem -LiteralPath $Root -Recurse -File -Filter $pattern -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -notmatch '\\(node_modules|\.git|\.idea|\.vscode|\.venv|venv|env|__pycache__|target|build|dist|logs|\.pytest_cache)\\' } |
            Select-Object -First 1
        if ($f) { return $f }
    }
    return $null
}

function Read-StartGen($Root) {
    $cfg = @{}
    $file = Join-Path $Root '.startgen'
    if (Test-Path -LiteralPath $file) {
        Get-Content -LiteralPath $file | ForEach-Object {
            $line = $_.Trim()
            if ($line -and -not $line.StartsWith('#') -and $line.Contains('=')) {
                $k, $v = $line.Split('=', 2)
                $cfg[$k.Trim().ToLower()] = $v.Trim()
            }
        }
    }
    return $cfg
}

function Test-PythonWeb($Root) {
    if (Test-Path (Join-Path $Root 'run_web.bat')) { return $true }
    if ((Test-Path (Join-Path $Root 'templates')) -and (Test-Path (Join-Path $Root 'static')) -and (Get-FirstFile $Root @('*.py'))) { return $true }
    foreach ($name in @('app.py','main.py','server.py')) {
        $file = Join-Path $Root $name
        if (Test-Path -LiteralPath $file) {
            $text = Get-Content -LiteralPath $file -Raw -ErrorAction SilentlyContinue
            if ($text -match 'Flask\(|FastAPI\(|Django|streamlit|gradio|uvicorn|app\.run\(') { return $true }
        }
    }
    $req = Join-Path $Root 'requirements.txt'
    if (Test-Path -LiteralPath $req) {
        $text = Get-Content -LiteralPath $req -Raw -ErrorAction SilentlyContinue
        if ($text -match '(?im)^\s*(flask|fastapi|django|streamlit|gradio|uvicorn|gunicorn)\b') { return $true }
    }
    return $false
}

function Detect-Type($Root) {
    $cfg = Read-StartGen $Root
    if ($cfg['type']) { return $cfg['type'].ToLower() }

    if (Test-Path (Join-Path $Root 'package.json')) { return 'nodejs' }
    if (Test-Path (Join-Path $Root 'tsconfig.json')) { return 'typescript' }
    if (Test-Path (Join-Path $Root 'pom.xml')) { return 'java_maven' }
    if ((Test-Path (Join-Path $Root 'build.gradle')) -or (Test-Path (Join-Path $Root 'build.gradle.kts'))) { return 'java_gradle' }
    if (Test-Path (Join-Path $Root 'go.mod')) { return 'go' }
    if (Test-Path (Join-Path $Root 'Cargo.toml')) { return 'rust' }
    if (Test-Path (Join-Path $Root 'composer.json')) { return 'php' }
    if (Test-Path (Join-Path $Root 'Gemfile')) { return 'ruby' }
    if (Test-Path (Join-Path $Root 'CMakeLists.txt')) { return 'cpp' }
    if ((Test-Path (Join-Path $Root 'Makefile')) -or (Test-Path (Join-Path $Root 'makefile'))) { return 'c' }
    if (Get-FirstFile $Root @('*.sln','*.csproj')) { return 'dotnet' }

    # Web projects are detected before generic language projects.
    # A Python web app should be shown as "web", not generic "python".
    if (Test-PythonWeb $Root) { return 'web' }

    if ((Test-Path (Join-Path $Root 'requirements.txt')) -or (Test-Path (Join-Path $Root 'pyproject.toml')) -or (Test-Path (Join-Path $Root 'setup.py')) -or (Get-FirstFile $Root @('*.py'))) { return 'python' }
    if (Get-FirstFile $Root @('*.ts')) { return 'typescript' }
    if (Get-FirstFile $Root @('*.js')) { return 'nodejs' }
    if (Get-FirstFile $Root @('*.java')) { return 'java' }
    if (Get-FirstFile $Root @('*.go')) { return 'go' }
    if (Get-FirstFile $Root @('*.rs')) { return 'rust' }
    if (Get-FirstFile $Root @('*.php')) { return 'php' }
    if (Get-FirstFile $Root @('*.cs')) { return 'dotnet' }
    if (Get-FirstFile $Root @('*.rb')) { return 'ruby' }
    if (Get-FirstFile $Root @('*.cpp','*.cc','*.cxx')) { return 'cpp' }
    if (Get-FirstFile $Root @('*.c')) { return 'c' }
    return 'unknown'
}

function Add-CommonHeader([System.Collections.Generic.List[string]]$L, [string]$Type) {
    $L.Add('@echo off')
    $L.Add('setlocal')
    $L.Add('chcp 65001 >nul')
    $L.Add('set "PYTHONUTF8=1"')
    $L.Add('set "PYTHONIOENCODING=utf-8"')
    $L.Add('cd /d "%~dp0"')
    $L.Add('title Project Starter')
    $L.Add('echo ========================================')
    $L.Add('echo   Project Starter')
    $L.Add('echo ========================================')
    $L.Add('echo.')
    $L.Add('echo [INFO] Working directory: %cd%')
    $L.Add("echo [INFO] Project type: $Type")
    $L.Add('echo.')
    $L.Add('if not exist logs mkdir logs >nul 2>nul')
    $L.Add('echo Started at %date% %time% > logs\start.log')
    $L.Add('if exist .startgen (')
    $L.Add('  for /f "usebackq tokens=1,* delims==" %%A in (".startgen") do (')
    $L.Add('    if /i "%%A"=="command" (')
    $L.Add('      echo [INFO] Running custom command from .startgen: %%B')
    $L.Add('      cmd /c "%%B"')
    $L.Add('      goto END')
    $L.Add('    )')
    $L.Add('  )')
    $L.Add(')')
}

function Add-End([System.Collections.Generic.List[string]]$L) {
    $L.Add('')
    $L.Add(':END')
    $L.Add('echo.')
    $L.Add('echo [INFO] Finished.')
    $L.Add('echo [INFO] If errors occurred, check this window or logs\start.log.')
    $L.Add('echo.')
    $L.Add('pause')
}

function Write-StarterBat($Root, $Type) {
    $cfg = Read-StartGen $Root
    $L = [System.Collections.Generic.List[string]]::new()
    Add-CommonHeader $L $Type

    switch ($Type) {
        'web' {
            $L.Add('if exist run_web.bat (')
            $L.Add('  echo [INFO] Found run_web.bat. Running it.')
            $L.Add('  call run_web.bat')
            $L.Add('  goto END')
            $L.Add(')')
            $L.Add('where python >nul 2>nul || (echo [ERROR] Python was not found in PATH.& goto END)')
            $L.Add('if exist .venv\Scripts\activate.bat call .venv\Scripts\activate.bat')
            $L.Add('if exist venv\Scripts\activate.bat call venv\Scripts\activate.bat')
            $L.Add('if exist env\Scripts\activate.bat call env\Scripts\activate.bat')
            $L.Add('if exist requirements.txt python -m pip install -r requirements.txt')
            $L.Add('if exist app.py (python app.py & goto END)')
            $L.Add('if exist main.py (python main.py & goto END)')
            $L.Add('if exist server.py (python server.py & goto END)')
            $L.Add('where flask >nul 2>nul && (flask run & goto END)')
            $L.Add('echo [ERROR] No web entry file was found.')
        }
        'python' {
            $L.Add('where python >nul 2>nul || (echo [ERROR] Python was not found in PATH.& goto END)')
            $L.Add('if exist .venv\Scripts\activate.bat call .venv\Scripts\activate.bat')
            $L.Add('if exist venv\Scripts\activate.bat call venv\Scripts\activate.bat')
            $L.Add('if exist env\Scripts\activate.bat call env\Scripts\activate.bat')
            $L.Add('if exist requirements.txt python -m pip install -r requirements.txt')
            $L.Add('if exist pytest.ini (python -m pytest & goto END)')
            $L.Add('if exist main.py (python main.py & goto END)')
            $L.Add('if exist app.py (python app.py & goto END)')
            $L.Add('if exist run.py (python run.py & goto END)')
            $L.Add('if exist manage.py (python manage.py runserver & goto END)')
            $L.Add('for /r %%F in (*.py) do (python "%%F" & goto END)')
            $L.Add('echo [ERROR] No Python entry file was found.')
        }
        'nodejs' {
            $L.Add('where node >nul 2>nul || (echo [ERROR] Node.js was not found in PATH.& goto END)')
            $L.Add('if exist package.json if not exist node_modules npm install')
            $L.Add('if exist package.json (')
            $L.Add('  findstr /c:"\"dev\"" package.json >nul && (npm run dev & goto END)')
            $L.Add('  findstr /c:"\"start\"" package.json >nul && (npm start & goto END)')
            $L.Add(')')
            $L.Add('if exist index.js (node index.js & goto END)')
            $L.Add('if exist server.js (node server.js & goto END)')
            $L.Add('if exist app.js (node app.js & goto END)')
            $L.Add('for /r %%F in (*.js) do (node "%%F" & goto END)')
            $L.Add('echo [ERROR] No JavaScript entry file was found.')
        }
        'typescript' {
            $L.Add('where node >nul 2>nul || (echo [ERROR] Node.js was not found in PATH.& goto END)')
            $L.Add('if exist package.json if not exist node_modules npm install')
            $L.Add('if exist package.json (')
            $L.Add('  findstr /c:"\"dev\"" package.json >nul && (npm run dev & goto END)')
            $L.Add('  findstr /c:"\"start\"" package.json >nul && (npm start & goto END)')
            $L.Add(')')
            $L.Add('where npx >nul 2>nul || (echo [ERROR] npx was not found in PATH.& goto END)')
            $L.Add('if exist src\main.ts (npx ts-node src\main.ts & goto END)')
            $L.Add('if exist src\index.ts (npx ts-node src\index.ts & goto END)')
            $L.Add('if exist index.ts (npx ts-node index.ts & goto END)')
            $L.Add('for /r %%F in (*.ts) do (npx ts-node "%%F" & goto END)')
        }
        'java_maven' { $L.Add('where mvn >nul 2>nul || (echo [ERROR] Maven was not found in PATH.& goto END)'); $L.Add('findstr /i "spring-boot" pom.xml >nul && (mvn spring-boot:run & goto END)'); $L.Add('mvn exec:java') }
        'java_gradle' { $L.Add('if exist gradlew.bat (call gradlew.bat bootRun & goto END)'); $L.Add('where gradle >nul 2>nul && (gradle bootRun & goto END)'); $L.Add('echo [ERROR] Gradle was not found in PATH.') }
        'java' { $L.Add('where javac >nul 2>nul || (echo [ERROR] javac was not found in PATH.& goto END)'); $L.Add('if not exist build mkdir build'); $L.Add('dir /s /b *.java > sources.txt'); $L.Add('javac -d build @sources.txt'); $L.Add('for /f "delims=" %%F in (''findstr /s /m /c:"public static void main" *.java'') do (java -cp build %%~nF & goto END)'); $L.Add('echo [ERROR] No Java main class was found.') }
        'go' { $L.Add('where go >nul 2>nul || (echo [ERROR] Go was not found in PATH.& goto END)'); $L.Add('go run .') }
        'rust' { $L.Add('where cargo >nul 2>nul || (echo [ERROR] Cargo was not found in PATH.& goto END)'); $L.Add('cargo run') }
        'php' { $L.Add('where php >nul 2>nul || (echo [ERROR] PHP was not found in PATH.& goto END)'); $L.Add('if exist composer.json where composer >nul 2>nul && composer install'); $L.Add('if exist public\index.php (php -S localhost:8000 -t public & goto END)'); $L.Add('if exist index.php (php -S localhost:8000 & goto END)'); $L.Add('for /r %%F in (*.php) do (php "%%F" & goto END)') }
        'dotnet' { $L.Add('where dotnet >nul 2>nul || (echo [ERROR] dotnet was not found in PATH.& goto END)'); $L.Add('dotnet run') }
        'ruby' { $L.Add('where ruby >nul 2>nul || (echo [ERROR] Ruby was not found in PATH.& goto END)'); $L.Add('if exist Gemfile where bundle >nul 2>nul && bundle install'); $L.Add('if exist app.rb (ruby app.rb & goto END)'); $L.Add('if exist main.rb (ruby main.rb & goto END)'); $L.Add('for /r %%F in (*.rb) do (ruby "%%F" & goto END)') }
        'c' { $L.Add('for %%F in (*.exe) do ("%%F" & goto END)'); $L.Add('if exist Makefile (where mingw32-make >nul 2>nul && (mingw32-make & goto END))'); $L.Add('if exist makefile (where make >nul 2>nul && (make & goto END))'); $L.Add('where gcc >nul 2>nul || (echo [ERROR] gcc was not found in PATH.& goto END)'); $L.Add('gcc *.c -o main.exe'); $L.Add('if exist main.exe main.exe') }
        'cpp' { $L.Add('for %%F in (*.exe) do ("%%F" & goto END)'); $L.Add('if exist CMakeLists.txt (where cmake >nul 2>nul && (cmake -S . -B build && cmake --build build & goto END))'); $L.Add('where g++ >nul 2>nul || (echo [ERROR] g++ was not found in PATH.& goto END)'); $L.Add('g++ *.cpp *.cc *.cxx -o main.exe'); $L.Add('if exist main.exe main.exe') }
        default { $L.Add("echo [ERROR] Unsupported project type: $Type") }
    }

    Add-End $L
    $batPath = Join-Path $Root 'start.bat'
    Set-Content -LiteralPath $batPath -Value ($L -join "`r`n") -Encoding ASCII

    # From now on only start.bat is generated. Remove older helper if it exists.
    $oldPs1 = Join-Path $Root 'start.ps1'
    if (Test-Path -LiteralPath $oldPs1) { Remove-Item -LiteralPath $oldPs1 -Force }
}

Clear-Host
Write-Host '========================================'
Write-Host '  Auto Start Script Generator v5'
Write-Host '========================================'
Write-Host ''

try {
    if ($InputArgs -and $InputArgs.Count -gt 0) {
        $inputPath = ($InputArgs -join ' ')
    } else {
        $inputPath = Read-Host 'Enter project path or file path'
    }

    $root = Get-ProjectRoot $inputPath
    Info "Analyzing project: $inputPath"
    Info "Project root selected: $root"

    $type = Detect-Type $root
    if ($type -eq 'unknown') {
        Err 'Cannot determine project type.'
        Err "No supported project markers or source files were found in: $root"
        Write-Host 'Supported types: web, python, nodejs, typescript, java_maven, java_gradle, java, go, rust, php, dotnet, ruby, c, cpp'
        exit 1
    }

    Info "Project type: $type"
    Write-StarterBat $root $type
    Info "start.bat generated at: $(Join-Path $root 'start.bat')"
    Info 'Only one startup file is generated now. No start.ps1 is created.'
} catch {
    Err $_.Exception.Message
    exit 1
}
