@echo off
chcp 65001 >nul
setlocal EnableExtensions EnableDelayedExpansion

title localGitCommit/push

echo ========================================
echo localGitprojectCommit/push
echo ========================================
echo.
echo Usage:
echo 1. Enter a project directory,the script checks or initializes the Git repository.
echo 2. selectcommitlocal pushremoterepository.
echo 3. default : C:\Users\Light\Desktop\[FolderName]
echo You can enter only a folder name, for example: MyProject
echo It resolves to: C:\Users\Light\Desktop\MyProject
echo.

where git >nul 2>nul
if errorlevel 1 (
 echo [ERROR] check Git,InstallGit for Windows:
 echo https://git-scm.com/download/win
 pause
 exit /b 1
)

set "BASE_DIR=C:\Users\Light\Desktop"

:INPUT_DIR
set "PROJECT_DIR="
set /p "PROJECT_DIR=Enter projectDirectorypathDesktop folder: "
if "%PROJECT_DIR%"=="" (
 echo [INFO] Directorycannot be empty.
 goto INPUT_DIR
)

rem If user input is not a full path, treat it as a folder name under Desktop
echo %PROJECT_DIR% | findstr /r "^[A-Za-z]:\\" >nul
if errorlevel 1 (
 set "PROJECT_DIR=%BASE_DIR%\%PROJECT_DIR%"
)

if not exist "%PROJECT_DIR%\" (
 echo [ERROR] Directorydoes not exist: %PROJECT_DIR%
 echo.
 goto INPUT_DIR
)

cd /d "%PROJECT_DIR%" || (
 echo [ERROR] Directory: %PROJECT_DIR%
 pause
 exit /b 1
)

echo.
echo currentprojectDirectory: %CD%
echo.

if not exist ".git\" (
 echo [INFO] currentdirectoryGitrepository.
 choice /c YN /m "Initialize as Git repository"
 if errorlevel 2 (
 echo Cancelled.led.
 pause
 exit /b 0
)
 git init
 if errorlevel 1 (
 echo [ERROR] git init Failed.
 pause
 exit /b 1
)
)

echo.
echo ========= =========
echo 1. file commitlocalGit
echo 2. file/commitpushremoterepository
echo 3. Show Git status only
echo 4. Set or update remote repository URL(origin)
echo 5. PullremoteUpdate(git pull)
echo 6. exit
echo ========================================
echo.
choice /c 123456 /m "Select an action"
set "OPT=%errorlevel%"

if "%OPT%"=="6" goto END
if "%OPT%"=="3" goto STATUS
if "%OPT%"=="4" goto SET_REMOTE
if "%OPT%"=="5" goto PULL
if "%OPT%"=="1" goto COMMIT_ONLY
if "%OPT%"=="2" goto COMMIT_PUSH

:STATUS
echo.
git status
echo.
pause
goto END

:SET_REMOTE
echo.
set "REMOTE_URL="
set /p "REMOTE_URL=Enter remote repository URL (e.g., https://github.com/user/repo.git or file:///D:/git/repo.git): "
if "%REMOTE_URL%"=="" (
 echo [ERROR] remote repository URLcannot be empty.
 pause
 goto END
)

git remote get-url origin >nul 2>nul
if errorlevel 1 (
 git remote add origin "%REMOTE_URL%"
) else (
 git remote set-url origin "%REMOTE_URL%"
)
if errorlevel 1 (
 echo [ERROR] set originFailed.
 pause
 exit /b 1
)
echo [DONE] Origin :
git remote get-url origin
echo.
pause
goto END

:PULL
echo.
set "BRANCH="
for /f "tokens=*" %%i in ('git branch --show-current 2^>nul') do set "BRANCH=%%i"
if "%BRANCH%"=="" set "BRANCH=main"
set /p "BRANCH=Enter pullbranch (press Enter to use current/default branch [%BRANCH%]): "
if "%BRANCH%"=="" set "BRANCH=main"
git pull origin "%BRANCH%"
echo.
pause
goto END

:COMMIT_ONLY
call :DO_COMMIT
goto END

:COMMIT_PUSH
call :DO_COMMIT
if errorlevel 1 goto END

git remote get-url origin >nul 2>nul
if errorlevel 1 (
 echo.
 echo [INFO] remoterepositoryorigin.
 choice /c YN /m "set origin"
 if errorlevel 2 goto END
 goto SET_REMOTE_AND_PUSH
)
goto PUSH

:SET_REMOTE_AND_PUSH
set "REMOTE_URL="
set /p "REMOTE_URL=Enter remote repository URL: "
if "%REMOTE_URL%"=="" (
 echo [ERROR] remote repository URLcannot be empty. pushCancelled.
 pause
 goto END
)
git remote add origin "%REMOTE_URL%" 2>nul || git remote set-url origin "%REMOTE_URL%"

:PUSH
echo.
set "BRANCH="
for /f "tokens=*" %%i in ('git branch --show-current 2^>nul') do set "BRANCH=%%i"
if "%BRANCH%"=="" (
 set "BRANCH=main"
 git branch -M main
)
set /p "BRANCH=Enter pushbranch (press Enter to use current/default branch [%BRANCH%]): "
if "%BRANCH%"=="" set "BRANCH=main"

echo [INFO] push origin/%BRANCH%...
git push -u origin "%BRANCH%"
if errorlevel 1 (
 echo [ERROR] PushFailed,checkremoteURL/permissions.
 pause
 exit /b 1
)
echo [DONE] PushDone.
pause
goto END

:DO_COMMIT
echo.
echo [INFO] currentGitstatus:
git status --short
echo.
choice /c YN /m "Run git add ."
if errorlevel 2 (
 echo commitCancelled.
 exit /b 1
)

git add .
if errorlevel 1 (
 echo [ERROR] git add Failed.
 pause
 exit /b 1
)

git diff --cached --quiet
if not errorlevel 1 (
 echo [INFO] staging area commit.
 pause
 exit /b 1
)

set "COMMIT_MSG="
set /p "COMMIT_MSG=Enter commit message(press Enter for default): "
if "%COMMIT_MSG%"=="" set "COMMIT_MSG=update project"

git commit -m "%COMMIT_MSG%"
if errorlevel 1 (
 echo [ERROR] git commit Failed,checkGit user/name config.
 echo Run: git config --global user.name "Your Name"
 echo Run: git config --global user.email "your@email.com"
 pause
 exit /b 1
)
echo [DONE] commitlocalGit.
exit /b 0

:END
echo.
echo Done.
endlocal
