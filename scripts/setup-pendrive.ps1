<#
.SYNOPSIS
    Instalador interativo Multi-Agent Portátil para Pendrive ou Disco Externo (Windows).
.DESCRIPTION
    Suporta instalação isolada e portátil de:
      [1] OpenCode Portable (com MCP agent-desktop)
      [2] Claude Code Portable (com Node.js portátil integrado)
      [3] GitHub Copilot CLI (com gh.exe portátil)
      [4] Antigravity CLI (Google DeepMind)
      [5] Todos os Agentes (Suíte Completa)
    Mantém isolamento estrito de variáveis de ambiente e dados em .\data\<agent>,
    workspace compartilhado em .\Projetos e skills em .\skills.
#>

[CmdletBinding()]
param(
    [switch]$Mock,
    [string]$TargetDir,
    [object[]]$Agents,
    [long]$SimulatedFreeSpace = 0
)

$ErrorActionPreference = 'Stop'
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$RepoRoot  = Split-Path -Parent $ScriptDir

$AgentCatalog = @{
    1 = @{
        Id             = 1
        Key            = 'opencode'
        Name           = 'OpenCode'
        DisplayName    = 'OpenCode Portable (com MCP agent-desktop)'
        EstimatedBytes = 120MB
        Launcher       = 'Iniciar OpenCode.bat'
        DataSubdir     = 'data\opencode'
    }
    2 = @{
        Id             = 2
        Key            = 'claude'
        Name           = 'Claude Code'
        DisplayName    = 'Claude Code Portable (com Node.js portátil integrado)'
        EstimatedBytes = 150MB
        Launcher       = 'Iniciar Claude Code.bat'
        DataSubdir     = 'data\claude'
    }
    3 = @{
        Id             = 3
        Key            = 'copilot'
        Name           = 'GitHub Copilot CLI'
        DisplayName    = 'GitHub Copilot CLI (com gh.exe portátil)'
        EstimatedBytes = 60MB
        Launcher       = 'Iniciar Copilot.bat'
        DataSubdir     = 'data\gh'
    }
    4 = @{
        Id             = 4
        Key            = 'antigravity'
        Name           = 'Antigravity CLI'
        DisplayName    = 'Antigravity CLI (Google DeepMind)'
        EstimatedBytes = 80MB
        Launcher       = 'Iniciar Antigravity.bat'
        DataSubdir     = 'data\antigravity'
    }
}

function Show-Header {
    if (-not $Mock) { Clear-Host }
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host "     INSTALADOR MULTI-AGENT PORTABLE PARA PENDRIVE          " -ForegroundColor White
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host ""
}

function Format-Bytes([long]$bytes) {
    if ($bytes -ge 1GB) { return "{0:N2} GB" -f ($bytes / 1GB) }
    if ($bytes -ge 1MB) { return "{0:N0} MB" -f ($bytes / 1MB) }
    return "{0:N0} KB" -f ($bytes / 1KB)
}

function Get-CandidateDrives {
    # Busca discos lógicos removíveis (DriveType = 2) ou fixos/externos (DriveType = 3), exceto C:
    $disks = Get-CimInstance Win32_LogicalDisk | Where-Object {
        $_.DeviceID -ne 'C:' -and $_.DriveType -in @(2, 3) -and $_.Size -gt 0
    }
    return $disks
}

function Resolve-AgentSelection([object[]]$RawSelection) {
    if (-not $RawSelection -or $RawSelection.Count -eq 0) { return @() }
    $joined = ($RawSelection | ForEach-Object { [string]$_ }) -join ','
    $tokens = $joined -split '[,\s]+' | Where-Object { $_ -ne '' }
    if ($tokens.Count -eq 0) { return @() }

    $selectedIds = New-Object System.Collections.Generic.List[int]
    foreach ($t in $tokens) {
        $clean = $t.Trim().ToUpperInvariant()
        if ($clean -eq '5' -or $clean -eq 'ALL' -or $clean -eq 'TODOS') {
            return @(1, 2, 3, 4)
        }
        $parsed = 0
        if (-not [int]::TryParse($clean, [ref]$parsed) -or $parsed -lt 1 -or $parsed -gt 4) {
            return @()
        }
        if (-not $selectedIds.Contains($parsed)) {
            $selectedIds.Add($parsed)
        }
    }
    return @($selectedIds | Sort-Object)
}

function Get-RequiredSpaceBytes([int[]]$SelectedAgentIds) {
    [long]$sum = 0
    foreach ($id in $SelectedAgentIds) {
        if ($AgentCatalog.Contains($id)) {
            $sum += [long]$AgentCatalog[$id].EstimatedBytes
        }
    }
    return $sum
}

function New-LauncherContent {
    param(
        [Parameter(Mandatory)][int]$AgentId
    )

    switch ($AgentId) {
        1 {
            return @'
@ECHO OFF
TITLE OpenCode Portable
SETLOCAL EnableExtensions

IF /I NOT "%~1"=="--no-banner" (
  ECHO.
  ECHO  =======================================================
  ECHO    OpenCode Portable
  ECHO    Initializing environment, skills, and tools...
  ECHO    Please wait a moment...
  ECHO  =======================================================
  ECHO.
)

SET "ROOT=%~dp0"
IF NOT "%ROOT%"=="%~d0\" IF "%ROOT:~-1%"=="\" SET "ROOT=%ROOT:~0,-1%"
IF "%ROOT:~-1%"=="\" SET "ROOT=%ROOT:~0,-1%"

IF /I "%~1"=="--update" GOTO :doupdate
IF /I "%~1"=="--atualizar" GOTO :doupdate

SET "DATA=%ROOT%\data\opencode"
IF NOT EXIST "%DATA%\config" MKDIR "%DATA%\config" 2>NUL
IF NOT EXIST "%DATA%\data"   MKDIR "%DATA%\data" 2>NUL
IF NOT EXIST "%DATA%\cache"  MKDIR "%DATA%\cache" 2>NUL
IF NOT EXIST "%DATA%\state"  MKDIR "%DATA%\state" 2>NUL
IF NOT EXIST "%DATA%\home"   MKDIR "%DATA%\home" 2>NUL
IF NOT EXIST "%DATA%\appdata\Roaming" MKDIR "%DATA%\appdata\Roaming" 2>NUL
IF NOT EXIST "%DATA%\appdata\Local"   MKDIR "%DATA%\appdata\Local" 2>NUL
SET "TMPROOT=%DATA%\tmp"
IF NOT EXIST "%TMPROOT%" MKDIR "%TMPROOT%" 2>NUL

IF NOT EXIST "%ROOT%\config\opencode.json" IF EXIST "%ROOT%\config\opencode.example.json" COPY /Y "%ROOT%\config\opencode.example.json" "%ROOT%\config\opencode.json" >NUL 2>&1

SET "XDG_CONFIG_HOME=%DATA%\config"
SET "XDG_DATA_HOME=%DATA%\data"
SET "XDG_CACHE_HOME=%DATA%\cache"
SET "XDG_STATE_HOME=%DATA%\state"
SET "USERPROFILE=%DATA%\home"
SET "HOME=%DATA%\home"
SET "APPDATA=%DATA%\appdata\Roaming"
SET "LOCALAPPDATA=%DATA%\appdata\Local"
SET "OPENCODE_CONFIG=%ROOT%\config\opencode.json"
SET "OPENCODE_DISABLE_MODELS_FETCH=1"
IF EXIST "%ROOT%\bin" SET "PATH=%ROOT%\bin;%PATH%"

SET "SKILLS_SRC=%ROOT%\skills"
IF EXIST "%SKILLS_SRC%" (
  IF NOT EXIST "%DATA%\config\opencode\skills" MKDIR "%DATA%\config\opencode\skills" 2>NUL
  XCOPY "%SKILLS_SRC%" "%DATA%\config\opencode\skills" /E /I /Y /Q >NUL 2>&1
)

SET "RAWTIME=%TIME: =0%"
SET "RAWTIME=%RAWTIME:/=-%"
SET "RAWTIME=%RAWTIME:.=-%"
SET "RAWTIME=%RAWTIME:,=-%"
SET "RAWTIME=%RAWTIME:;=-%"
SET "RUNID=run-%RAWTIME:~0,2%%RAWTIME:~3,2%%RAWTIME:~6,2%-%RANDOM%"
SET "RUN_TMP=%TMPROOT%\%RUNID%"
MKDIR "%RUN_TMP%" 2>NUL
SET "CLEAN_RUN_TMP=1"
IF NOT EXIST "%RUN_TMP%" (SET "CLEAN_RUN_TMP=0" & SET "RUN_TMP=%TMPROOT%")

SET "TMP=%RUN_TMP%"
SET "TEMP=%RUN_TMP%"
SET "TMPDIR=%RUN_TMP%"

IF EXIST "%ROOT%\Projetos" CD /D "%ROOT%\Projetos"

IF /I "%~1"=="--test-env" (
  SETLOCAL EnableDelayedExpansion
  ECHO CWD=!CD!
  ECHO USERPROFILE=!USERPROFILE!
  ECHO HOME=!HOME!
  ECHO APPDATA=!APPDATA!
  ECHO LOCALAPPDATA=!LOCALAPPDATA!
  ECHO XDG_CONFIG_HOME=!XDG_CONFIG_HOME!
  ECHO XDG_DATA_HOME=!XDG_DATA_HOME!
  ECHO XDG_CACHE_HOME=!XDG_CACHE_HOME!
  ECHO XDG_STATE_HOME=!XDG_STATE_HOME!
  ECHO OPENCODE_CONFIG=!OPENCODE_CONFIG!
  ECHO TMP=!TMP!
  ECHO TEMP=!TEMP!
  ECHO TMPDIR=!TMPDIR!
  ENDLOCAL
  SET "EXITCODE=0"
  GOTO :afterrun
)

IF /I "%~1"=="--test-fail" (
  SET "EXITCODE=1"
  GOTO :afterrun
)

SET "BIN=%ROOT%\bin\opencode.exe"
IF NOT EXIST "%BIN%" (
  ECHO [opencode-portable] ERROR: "%BIN%" not found.
  SET "EXITCODE=1"
  GOTO :afterrun
)

"%BIN%" %*
SET "EXITCODE=%ERRORLEVEL%"

:afterrun
IF "%CLEAN_RUN_TMP%"=="1" IF EXIST "%RUN_TMP%" RMDIR /S /Q "%RUN_TMP%" 2>NUL
SETLOCAL EnableDelayedExpansion
IF NOT "!EXITCODE!"=="0" (
  ECHO.
  ECHO Process exited with code !EXITCODE!.
  ECHO Press any key to close this window...
  IF NOT DEFINED PORTABLE_NONINTERACTIVE PAUSE >NUL
)
ENDLOCAL & EXIT /B %EXITCODE%

:doupdate
SHIFT /1
powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\bin\update.ps1" %1 %2 %3 %4 %5
SET "UPD_RC=%ERRORLEVEL%"
IF NOT DEFINED PORTABLE_NONINTERACTIVE (
  ECHO.
  ECHO Press any key to exit...
  PAUSE >NUL
)
EXIT /B %UPD_RC%
'@
        }
        2 {
            return @'
@ECHO OFF
TITLE Claude Code Portable
SETLOCAL EnableExtensions

IF /I NOT "%~1"=="--no-banner" (
  ECHO.
  ECHO  =======================================================
  ECHO    Claude Code Portable
  ECHO    Initializing environment, skills, and tools...
  ECHO    Please wait a moment...
  ECHO  =======================================================
  ECHO.
)

SET "ROOT=%~dp0"
IF NOT "%ROOT%"=="%~d0\" IF "%ROOT:~-1%"=="\" SET "ROOT=%ROOT:~0,-1%"
IF "%ROOT:~-1%"=="\" SET "ROOT=%ROOT:~0,-1%"

IF /I "%~1"=="--update" GOTO :doupdate
IF /I "%~1"=="--atualizar" GOTO :doupdate

SET "DATA=%ROOT%\data\claude"
IF NOT EXIST "%DATA%\.claude"         MKDIR "%DATA%\.claude" 2>NUL
IF NOT EXIST "%DATA%\config"          MKDIR "%DATA%\config" 2>NUL
IF NOT EXIST "%DATA%\data"            MKDIR "%DATA%\data" 2>NUL
IF NOT EXIST "%DATA%\cache"           MKDIR "%DATA%\cache" 2>NUL
IF NOT EXIST "%DATA%\state"           MKDIR "%DATA%\state" 2>NUL
IF NOT EXIST "%DATA%\npm-cache"       MKDIR "%DATA%\npm-cache" 2>NUL
IF NOT EXIST "%DATA%\appdata\Roaming" MKDIR "%DATA%\appdata\Roaming" 2>NUL
IF NOT EXIST "%DATA%\appdata\Local"   MKDIR "%DATA%\appdata\Local" 2>NUL
SET "TMPROOT=%DATA%\tmp"
IF NOT EXIST "%TMPROOT%" MKDIR "%TMPROOT%" 2>NUL

REM Isolamento estrito de USERPROFILE / HOME para que ~/.claude e ~/.claude.json fiquem em .\data\claude
SET "USERPROFILE=%DATA%"
SET "HOME=%DATA%"
SET "CLAUDE_CONFIG_DIR=%DATA%\.claude"
SET "APPDATA=%DATA%\appdata\Roaming"
SET "LOCALAPPDATA=%DATA%\appdata\Local"
SET "XDG_CONFIG_HOME=%DATA%\config"
SET "XDG_DATA_HOME=%DATA%\data"
SET "XDG_CACHE_HOME=%DATA%\cache"
SET "XDG_STATE_HOME=%DATA%\state"
SET "NPM_CONFIG_CACHE=%DATA%\npm-cache"
SET "NPM_CONFIG_USERCONFIG=%DATA%\.npmrc"
SET "PATH=%ROOT%\bin\node;%ROOT%\bin;%PATH%"

SET "SKILLS_SRC=%ROOT%\skills"
IF EXIST "%SKILLS_SRC%" (
  IF NOT EXIST "%DATA%\.claude\skills" MKDIR "%DATA%\.claude\skills" 2>NUL
  XCOPY "%SKILLS_SRC%" "%DATA%\.claude\skills" /E /I /Y /Q >NUL 2>&1
)

SET "RAWTIME=%TIME: =0%"
SET "RAWTIME=%RAWTIME:/=-%"
SET "RAWTIME=%RAWTIME:.=-%"
SET "RAWTIME=%RAWTIME:,=-%"
SET "RAWTIME=%RAWTIME:;=-%"
SET "RUNID=run-%RAWTIME:~0,2%%RAWTIME:~3,2%%RAWTIME:~6,2%-%RANDOM%"
SET "RUN_TMP=%TMPROOT%\%RUNID%"
MKDIR "%RUN_TMP%" 2>NUL
SET "CLEAN_RUN_TMP=1"
IF NOT EXIST "%RUN_TMP%" (SET "CLEAN_RUN_TMP=0" & SET "RUN_TMP=%TMPROOT%")

SET "TMP=%RUN_TMP%"
SET "TEMP=%RUN_TMP%"
SET "TMPDIR=%RUN_TMP%"

IF EXIST "%ROOT%\Projetos" CD /D "%ROOT%\Projetos"

IF /I "%~1"=="--test-env" (
  SETLOCAL EnableDelayedExpansion
  ECHO CWD=!CD!
  ECHO USERPROFILE=!USERPROFILE!
  ECHO HOME=!HOME!
  ECHO CLAUDE_CONFIG_DIR=!CLAUDE_CONFIG_DIR!
  ECHO APPDATA=!APPDATA!
  ECHO LOCALAPPDATA=!LOCALAPPDATA!
  ECHO XDG_CONFIG_HOME=!XDG_CONFIG_HOME!
  ECHO XDG_DATA_HOME=!XDG_DATA_HOME!
  ECHO XDG_CACHE_HOME=!XDG_CACHE_HOME!
  ECHO XDG_STATE_HOME=!XDG_STATE_HOME!
  ECHO NPM_CONFIG_CACHE=!NPM_CONFIG_CACHE!
  ECHO TMP=!TMP!
  ECHO TEMP=!TEMP!
  ECHO TMPDIR=!TMPDIR!
  ENDLOCAL
  SET "EXITCODE=0"
  GOTO :afterrun
)

IF /I "%~1"=="--test-fail" (
  SET "EXITCODE=1"
  GOTO :afterrun
)

IF EXIST "%ROOT%\bin\node\claude.cmd" (
  CALL "%ROOT%\bin\node\claude.cmd" %*
  SET "EXITCODE=%ERRORLEVEL%"
  GOTO :afterrun
)
IF EXIST "%ROOT%\bin\claude.exe" (
  "%ROOT%\bin\claude.exe" %*
  SET "EXITCODE=%ERRORLEVEL%"
  GOTO :afterrun
)
IF EXIST "%ROOT%\bin\node\node.exe" (
  "%ROOT%\bin\node\node.exe" "%ROOT%\bin\node\node_modules\@anthropic-ai\claude-code\cli.js" %*
  SET "EXITCODE=%ERRORLEVEL%"
  GOTO :afterrun
)

ECHO [claude-portable] ERROR: Claude Code runtime not found in "%ROOT%\bin\node".
SET "EXITCODE=1"

:afterrun
IF "%CLEAN_RUN_TMP%"=="1" IF EXIST "%RUN_TMP%" RMDIR /S /Q "%RUN_TMP%" 2>NUL
SETLOCAL EnableDelayedExpansion
IF NOT "!EXITCODE!"=="0" (
  ECHO.
  ECHO Process exited with code !EXITCODE!.
  ECHO Press any key to close this window...
  IF NOT DEFINED PORTABLE_NONINTERACTIVE PAUSE >NUL
)
ENDLOCAL & EXIT /B %EXITCODE%

:doupdate
SHIFT /1
powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\bin\update.ps1" %1 %2 %3 %4 %5
SET "UPD_RC=%ERRORLEVEL%"
IF NOT DEFINED PORTABLE_NONINTERACTIVE (
  ECHO.
  ECHO Press any key to exit...
  PAUSE >NUL
)
EXIT /B %UPD_RC%
'@
        }
        3 {
            return @'
@ECHO OFF
TITLE GitHub Copilot CLI Portable
SETLOCAL EnableExtensions

IF /I NOT "%~1"=="--no-banner" (
  ECHO.
  ECHO  =======================================================
  ECHO    GitHub Copilot CLI Portable
  ECHO    Initializing environment, skills, and tools...
  ECHO    Please wait a moment...
  ECHO  =======================================================
  ECHO.
)

SET "ROOT=%~dp0"
IF NOT "%ROOT%"=="%~d0\" IF "%ROOT:~-1%"=="\" SET "ROOT=%ROOT:~0,-1%"
IF "%ROOT:~-1%"=="\" SET "ROOT=%ROOT:~0,-1%"

IF /I "%~1"=="--update" GOTO :doupdate
IF /I "%~1"=="--atualizar" GOTO :doupdate

SET "DATA=%ROOT%\data\gh"
IF NOT EXIST "%DATA%\config"          MKDIR "%DATA%\config" 2>NUL
IF NOT EXIST "%DATA%\data"            MKDIR "%DATA%\data" 2>NUL
IF NOT EXIST "%DATA%\cache"           MKDIR "%DATA%\cache" 2>NUL
IF NOT EXIST "%DATA%\state"           MKDIR "%DATA%\state" 2>NUL
IF NOT EXIST "%DATA%\extensions"      MKDIR "%DATA%\extensions" 2>NUL
IF NOT EXIST "%DATA%\appdata\Roaming" MKDIR "%DATA%\appdata\Roaming" 2>NUL
IF NOT EXIST "%DATA%\appdata\Local"   MKDIR "%DATA%\appdata\Local" 2>NUL
SET "TMPROOT=%DATA%\tmp"
IF NOT EXIST "%TMPROOT%" MKDIR "%TMPROOT%" 2>NUL

REM Isolamento estrito de GH_CONFIG_DIR em .\data\gh
SET "GH_CONFIG_DIR=%DATA%"
SET "GH_DATA_DIR=%DATA%\data"
SET "GH_STATE_DIR=%DATA%\state"
SET "USERPROFILE=%DATA%"
SET "HOME=%DATA%"
SET "APPDATA=%DATA%\appdata\Roaming"
SET "LOCALAPPDATA=%DATA%\appdata\Local"
SET "XDG_CONFIG_HOME=%DATA%\config"
SET "XDG_DATA_HOME=%DATA%\data"
SET "XDG_CACHE_HOME=%DATA%\cache"
SET "XDG_STATE_HOME=%DATA%\state"
IF EXIST "%ROOT%\bin" SET "PATH=%ROOT%\bin;%PATH%"

SET "SKILLS_SRC=%ROOT%\skills"
IF EXIST "%SKILLS_SRC%" (
  IF NOT EXIST "%DATA%\skills" MKDIR "%DATA%\skills" 2>NUL
  XCOPY "%SKILLS_SRC%" "%DATA%\skills" /E /I /Y /Q >NUL 2>&1
)

SET "RAWTIME=%TIME: =0%"
SET "RAWTIME=%RAWTIME:/=-%"
SET "RAWTIME=%RAWTIME:.=-%"
SET "RAWTIME=%RAWTIME:,=-%"
SET "RAWTIME=%RAWTIME:;=-%"
SET "RUNID=run-%RAWTIME:~0,2%%RAWTIME:~3,2%%RAWTIME:~6,2%-%RANDOM%"
SET "RUN_TMP=%TMPROOT%\%RUNID%"
MKDIR "%RUN_TMP%" 2>NUL
SET "CLEAN_RUN_TMP=1"
IF NOT EXIST "%RUN_TMP%" (SET "CLEAN_RUN_TMP=0" & SET "RUN_TMP=%TMPROOT%")

SET "TMP=%RUN_TMP%"
SET "TEMP=%RUN_TMP%"
SET "TMPDIR=%RUN_TMP%"

IF EXIST "%ROOT%\Projetos" CD /D "%ROOT%\Projetos"

IF /I "%~1"=="--test-env" (
  SETLOCAL EnableDelayedExpansion
  ECHO CWD=!CD!
  ECHO GH_CONFIG_DIR=!GH_CONFIG_DIR!
  ECHO USERPROFILE=!USERPROFILE!
  ECHO HOME=!HOME!
  ECHO APPDATA=!APPDATA!
  ECHO LOCALAPPDATA=!LOCALAPPDATA!
  ECHO XDG_CONFIG_HOME=!XDG_CONFIG_HOME!
  ECHO XDG_DATA_HOME=!XDG_DATA_HOME!
  ECHO XDG_CACHE_HOME=!XDG_CACHE_HOME!
  ECHO XDG_STATE_HOME=!XDG_STATE_HOME!
  ECHO TMP=!TMP!
  ECHO TEMP=!TEMP!
  ECHO TMPDIR=!TMPDIR!
  ENDLOCAL
  SET "EXITCODE=0"
  GOTO :afterrun
)

IF /I "%~1"=="--test-fail" (
  SET "EXITCODE=1"
  GOTO :afterrun
)

SET "BIN=%ROOT%\bin\gh.exe"
IF NOT EXIST "%BIN%" (
  ECHO [copilot-portable] ERROR: "%BIN%" not found.
  SET "EXITCODE=1"
  GOTO :afterrun
)

IF /I "%~1"=="copilot" (
  "%BIN%" %*
) ELSE (
  "%BIN%" copilot %*
)
SET "EXITCODE=%ERRORLEVEL%"

:afterrun
IF "%CLEAN_RUN_TMP%"=="1" IF EXIST "%RUN_TMP%" RMDIR /S /Q "%RUN_TMP%" 2>NUL
SETLOCAL EnableDelayedExpansion
IF NOT "!EXITCODE!"=="0" (
  ECHO.
  ECHO Process exited with code !EXITCODE!.
  ECHO Press any key to close this window...
  IF NOT DEFINED PORTABLE_NONINTERACTIVE PAUSE >NUL
)
ENDLOCAL & EXIT /B %EXITCODE%

:doupdate
SHIFT /1
powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\bin\update.ps1" %1 %2 %3 %4 %5
SET "UPD_RC=%ERRORLEVEL%"
IF NOT DEFINED PORTABLE_NONINTERACTIVE (
  ECHO.
  ECHO Press any key to exit...
  PAUSE >NUL
)
EXIT /B %UPD_RC%
'@
        }
        4 {
            return @'
@ECHO OFF
TITLE Antigravity CLI Portable
SETLOCAL EnableExtensions

IF /I NOT "%~1"=="--no-banner" (
  ECHO.
  ECHO  =======================================================
  ECHO    Antigravity CLI Portable
  ECHO    Initializing environment, skills, and tools...
  ECHO    Please wait a moment...
  ECHO  =======================================================
  ECHO.
)

SET "ROOT=%~dp0"
IF NOT "%ROOT%"=="%~d0\" IF "%ROOT:~-1%"=="\" SET "ROOT=%ROOT:~0,-1%"
IF "%ROOT:~-1%"=="\" SET "ROOT=%ROOT:~0,-1%"

IF /I "%~1"=="--update" GOTO :doupdate
IF /I "%~1"=="--atualizar" GOTO :doupdate

SET "DATA=%ROOT%\data\antigravity"
IF NOT EXIST "%DATA%\.gemini"         MKDIR "%DATA%\.gemini" 2>NUL
IF NOT EXIST "%DATA%\config"          MKDIR "%DATA%\config" 2>NUL
IF NOT EXIST "%DATA%\data"            MKDIR "%DATA%\data" 2>NUL
IF NOT EXIST "%DATA%\cache"           MKDIR "%DATA%\cache" 2>NUL
IF NOT EXIST "%DATA%\state"           MKDIR "%DATA%\state" 2>NUL
IF NOT EXIST "%DATA%\appdata\Roaming" MKDIR "%DATA%\appdata\Roaming" 2>NUL
IF NOT EXIST "%DATA%\appdata\Local"   MKDIR "%DATA%\appdata\Local" 2>NUL
SET "TMPROOT=%DATA%\tmp"
IF NOT EXIST "%TMPROOT%" MKDIR "%TMPROOT%" 2>NUL

REM Isolamento estrito de GEMINI_HOME, ANTIGRAVITY_APP_DATA_DIR e .gemini em .\data\antigravity
SET "GEMINI_HOME=%DATA%\.gemini"
SET "ANTIGRAVITY_HOME=%DATA%"
SET "ANTIGRAVITY_CLI_HOME=%DATA%\.gemini\antigravity-cli"
SET "ANTIGRAVITY_APP_DATA_DIR=%DATA%\.gemini\antigravity-cli"
SET "USERPROFILE=%DATA%"
SET "HOME=%DATA%"
SET "APPDATA=%DATA%\appdata\Roaming"
SET "LOCALAPPDATA=%DATA%\appdata\Local"
SET "XDG_CONFIG_HOME=%DATA%\config"
SET "XDG_DATA_HOME=%DATA%\data"
SET "XDG_CACHE_HOME=%DATA%\cache"
SET "XDG_STATE_HOME=%DATA%\state"
IF EXIST "%ROOT%\bin" SET "PATH=%ROOT%\bin;%PATH%"

SET "SKILLS_SRC=%ROOT%\skills"
IF EXIST "%SKILLS_SRC%" (
  IF NOT EXIST "%DATA%\.gemini\skills" MKDIR "%DATA%\.gemini\skills" 2>NUL
  XCOPY "%SKILLS_SRC%" "%DATA%\.gemini\skills" /E /I /Y /Q >NUL 2>&1
)

SET "RAWTIME=%TIME: =0%"
SET "RAWTIME=%RAWTIME:/=-%"
SET "RAWTIME=%RAWTIME:.=-%"
SET "RAWTIME=%RAWTIME:,=-%"
SET "RAWTIME=%RAWTIME:;=-%"
SET "RUNID=run-%RAWTIME:~0,2%%RAWTIME:~3,2%%RAWTIME:~6,2%-%RANDOM%"
SET "RUN_TMP=%TMPROOT%\%RUNID%"
MKDIR "%RUN_TMP%" 2>NUL
SET "CLEAN_RUN_TMP=1"
IF NOT EXIST "%RUN_TMP%" (SET "CLEAN_RUN_TMP=0" & SET "RUN_TMP=%TMPROOT%")

SET "TMP=%RUN_TMP%"
SET "TEMP=%RUN_TMP%"
SET "TMPDIR=%RUN_TMP%"

IF EXIST "%ROOT%\Projetos" CD /D "%ROOT%\Projetos"

IF /I "%~1"=="--test-env" (
  SETLOCAL EnableDelayedExpansion
  ECHO CWD=!CD!
  ECHO GEMINI_HOME=!GEMINI_HOME!
  ECHO ANTIGRAVITY_HOME=!ANTIGRAVITY_HOME!
  ECHO USERPROFILE=!USERPROFILE!
  ECHO HOME=!HOME!
  ECHO APPDATA=!APPDATA!
  ECHO LOCALAPPDATA=!LOCALAPPDATA!
  ECHO XDG_CONFIG_HOME=!XDG_CONFIG_HOME!
  ECHO XDG_DATA_HOME=!XDG_DATA_HOME!
  ECHO XDG_CACHE_HOME=!XDG_CACHE_HOME!
  ECHO XDG_STATE_HOME=!XDG_STATE_HOME!
  ECHO TMP=!TMP!
  ECHO TEMP=!TEMP!
  ECHO TMPDIR=!TMPDIR!
  ENDLOCAL
  SET "EXITCODE=0"
  GOTO :afterrun
)

IF /I "%~1"=="--test-fail" (
  SET "EXITCODE=1"
  GOTO :afterrun
)

IF EXIST "%ROOT%\bin\antigravity.exe" (
  "%ROOT%\bin\antigravity.exe" %*
  SET "EXITCODE=%ERRORLEVEL%"
  GOTO :afterrun
)
IF EXIST "%ROOT%\bin\antigravity.cmd" (
  CALL "%ROOT%\bin\antigravity.cmd" %*
  SET "EXITCODE=%ERRORLEVEL%"
  GOTO :afterrun
)

ECHO [antigravity-portable] ERROR: Antigravity CLI binary not found in "%ROOT%\bin".
SET "EXITCODE=1"

:afterrun
IF "%CLEAN_RUN_TMP%"=="1" IF EXIST "%RUN_TMP%" RMDIR /S /Q "%RUN_TMP%" 2>NUL
SETLOCAL EnableDelayedExpansion
IF NOT "!EXITCODE!"=="0" (
  ECHO.
  ECHO Process exited with code !EXITCODE!.
  ECHO Press any key to close this window...
  IF NOT DEFINED PORTABLE_NONINTERACTIVE PAUSE >NUL
)
ENDLOCAL & EXIT /B %EXITCODE%

:doupdate
SHIFT /1
powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\bin\update.ps1" %1 %2 %3 %4 %5
SET "UPD_RC=%ERRORLEVEL%"
IF NOT DEFINED PORTABLE_NONINTERACTIVE (
  ECHO.
  ECHO Press any key to exit...
  PAUSE >NUL
)
EXIT /B %UPD_RC%
'@
        }
    }
}

function New-MockBinary([string]$OutExePath) {
    $parent = Split-Path -Parent $OutExePath
    if (-not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    $csc = "C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
    if (Test-Path -LiteralPath $csc) {
        $tmpCs = Join-Path $env:TEMP ("mock-agent-" + [Guid]::NewGuid().ToString('N') + ".cs")
        $csCode = @'
using System;
class Program {
    static int Main(string[] args) {
        foreach (string a in args) {
            if (string.Equals(a, "--fail", StringComparison.OrdinalIgnoreCase)) return 42;
            if (string.Equals(a, "--version", StringComparison.OrdinalIgnoreCase)) {
                Console.WriteLine("1.0.0-mock");
                return 0;
            }
        }
        Console.WriteLine("CWD=" + Environment.CurrentDirectory);
        string[] vars = new string[] {
            "USERPROFILE", "HOME", "APPDATA", "LOCALAPPDATA",
            "XDG_CONFIG_HOME", "XDG_DATA_HOME", "XDG_CACHE_HOME", "XDG_STATE_HOME",
            "OPENCODE_CONFIG", "CLAUDE_CONFIG_DIR", "GH_CONFIG_DIR", "GEMINI_HOME",
            "ANTIGRAVITY_HOME", "TMP", "TEMP", "TMPDIR"
        };
        foreach (string v in vars) {
            Console.WriteLine(v + "=" + (Environment.GetEnvironmentVariable(v) ?? ""));
        }
        Console.WriteLine("ARGS=" + string.Join(" ", args));
        return 0;
    }
}
'@
        try {
            [System.IO.File]::WriteAllText($tmpCs, $csCode)
            & $csc /nologo /target:exe "/out:$OutExePath" $tmpCs | Out-Null
        }
        finally {
            if (Test-Path -LiteralPath $tmpCs) { Remove-Item -LiteralPath $tmpCs -Force -ErrorAction SilentlyContinue }
        }
    }
    if (-not (Test-Path -LiteralPath $OutExePath)) {
        [System.IO.File]::WriteAllText($OutExePath, "MOCK_BINARY")
    }
}

# ============================================================
# 1. Determinação da Unidade / Diretório de Destino
# ============================================================
$TargetDrive = $null
[long]$AvailableFreeSpace = 0

if ($TargetDir) {
    $resolvedTarget = [System.IO.Path]::GetFullPath($TargetDir)
    # Bloqueio estrito da raiz da unidade C:
    if ($resolvedTarget.TrimEnd('\') -ieq 'C:') {
        throw "ERRO DE SEGURANÇA: A raiz da unidade de sistema C: não pode ser usada como destino."
    }
    if (-not (Test-Path -LiteralPath $resolvedTarget)) {
        New-Item -ItemType Directory -Path $resolvedTarget -Force | Out-Null
    }
    $TargetDrive = $resolvedTarget
    if ($SimulatedFreeSpace -gt 0) {
        $AvailableFreeSpace = $SimulatedFreeSpace
    } else {
        $driveRoot = [System.IO.Path]::GetPathRoot($resolvedTarget).TrimEnd('\')
        $diskInfo = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$driveRoot'" -ErrorAction SilentlyContinue
        $AvailableFreeSpace = if ($diskInfo) { [long]$diskInfo.FreeSpace } else { 10GB }
    }
} else {
    $targetDisk = $null
    while ($null -eq $targetDisk) {
        Show-Header
        Write-Host "[1/3] Procurando unidades removíveis / pendrives..." -ForegroundColor Yellow

        $candidates = @(Get-CandidateDrives)
        if ($candidates.Count -eq 0) {
            Write-Host ""
            Write-Host "Nenhum pendrive ou unidade externa foi detectada." -ForegroundColor Red
            Write-Host "Conecte o seu pendrive na porta USB e pressione ENTER para tentar novamente." -ForegroundColor Gray
            Write-Host "Ou digite 'Q' para cancelar e sair." -ForegroundColor Gray
            $resp = Read-Host "> "
            if ($resp -and $resp.Trim().ToUpperInvariant() -eq 'Q') {
                Write-Host "Instalação cancelada." -ForegroundColor Yellow
                return
            }
            continue
        }

        Write-Host ""
        Write-Host "Unidades disponíveis encontradas:" -ForegroundColor Green
        Write-Host "------------------------------------------------------------" -ForegroundColor Gray

        for ($i = 0; $i -lt $candidates.Count; $i++) {
            $d = $candidates[$i]
            $typeLabel = if ($d.DriveType -eq 2) { "Pendrive / Removível" } else { "Disco USB / Secundário" }
            $volName = if ([string]::IsNullOrWhiteSpace($d.VolumeName)) { "(sem nome)" } else { $d.VolumeName }
            $free = Format-Bytes $d.FreeSpace
            $total = Format-Bytes $d.Size
            $fs = $d.FileSystem

            Write-Host (" [{0}] {1}\ [{2}] - {3} livres de {4} ({5}, {6})" -f ($i + 1), $d.DeviceID, $volName, $free, $total, $fs, $typeLabel) -ForegroundColor White
        }
        Write-Host "------------------------------------------------------------" -ForegroundColor Gray
        Write-Host ""
        Write-Host "Digite o número da unidade onde deseja instalar (1-$($candidates.Count)) ou 'R' para atualizar a lista, 'Q' para sair:" -ForegroundColor Cyan
        $choice = Read-Host "> "

        if ($choice -and $choice.Trim().ToUpperInvariant() -eq 'Q') {
            Write-Host "Instalação cancelada pelo usuário." -ForegroundColor Yellow
            return
        }
        if ($choice -and $choice.Trim().ToUpperInvariant() -eq 'R') {
            continue
        }

        $idx = 0
        if ([int]::TryParse($choice, [ref]$idx) -and $idx -ge 1 -and $idx -le $candidates.Count) {
            $selected = $candidates[$idx - 1]
            if ($selected.DeviceID -ieq 'C:') {
                Write-Host "ERRO DE SEGURANÇA: A unidade de sistema C: não pode ser usada." -ForegroundColor Red
                Start-Sleep 2
                continue
            }
            $targetDisk = $selected
        } else {
            Write-Host "Opção inválida. Tente novamente." -ForegroundColor Red
            Start-Sleep 1
        }
    }
    $TargetDrive = $targetDisk.DeviceID + "\"
    $AvailableFreeSpace = if ($SimulatedFreeSpace -gt 0) { $SimulatedFreeSpace } else { [long]$targetDisk.FreeSpace }
}

# ============================================================
# 2. Menu Interativo de Seleção de Agentes
# ============================================================
$SelectedAgentIds = @(Resolve-AgentSelection $Agents)

while ($SelectedAgentIds.Count -eq 0) {
    Show-Header
    Write-Host "Unidade de destino: " -NoNewline
    Write-Host "$TargetDrive" -ForegroundColor Green
    Write-Host ""
    Write-Host "[2/3] Selecione os agentes que deseja instalar no pendrive:" -ForegroundColor Yellow
    Write-Host "------------------------------------------------------------" -ForegroundColor Gray
    Write-Host "  [1] OpenCode Portable (com MCP agent-desktop)             (~120 MB)" -ForegroundColor White
    Write-Host "  [2] Claude Code Portable (com Node.js portátil integrado) (~150 MB)" -ForegroundColor White
    Write-Host "  [3] GitHub Copilot CLI (com gh.exe portátil)              (~60 MB)" -ForegroundColor White
    Write-Host "  [4] Antigravity CLI (Google DeepMind)                     (~80 MB)" -ForegroundColor White
    Write-Host "  [5] Todos os Agentes (Suíte Completa)                     (~410 MB)" -ForegroundColor Green
    Write-Host "------------------------------------------------------------" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Digite sua escolha (ex: 1, 1,2, 1,3,4 ou 5) ou 'Q' para sair:" -ForegroundColor Cyan
    $agentInput = Read-Host "> "
    if ($agentInput -and $agentInput.Trim().ToUpperInvariant() -eq 'Q') {
        Write-Host "Instalação cancelada pelo usuário." -ForegroundColor Yellow
        return
    }
    $SelectedAgentIds = @(Resolve-AgentSelection @($agentInput))
    if ($SelectedAgentIds.Count -eq 0) {
        Write-Host "Seleção inválida. Escolha números entre 1 e 5 (ex: 1,2 ou 5)." -ForegroundColor Red
        Start-Sleep 1
    }
}

# ============================================================
# 3. Cálculo e Validação de Espaço Livre
# ============================================================
[long]$RequiredBytes = Get-RequiredSpaceBytes $SelectedAgentIds
$selectedNames = ($SelectedAgentIds | ForEach-Object { $AgentCatalog[$_].Name }) -join ', '

Write-Host ""
Write-Host "Agentes selecionados:  $selectedNames" -ForegroundColor Cyan
Write-Host ("Espaço estimado:       {0}" -f (Format-Bytes $RequiredBytes)) -ForegroundColor White
Write-Host ("Espaço livre na mídia: {0}" -f (Format-Bytes $AvailableFreeSpace)) -ForegroundColor White

if ($AvailableFreeSpace -lt $RequiredBytes) {
    $msg = ("Espaço livre insuficiente na unidade ({0} livres, necessário pelo menos {1} para: {2})." -f (Format-Bytes $AvailableFreeSpace), (Format-Bytes $RequiredBytes), $selectedNames)
    Write-Host ""
    Write-Host "[ALERTA DE ESPAÇO] $msg" -ForegroundColor Red
    if ($Mock -or $TargetDir) {
        throw $msg
    }
    $cont = Read-Host "Deseja tentar continuar mesmo assim? [s/N]"
    if (-not $cont -or $cont.Trim().ToUpperInvariant() -ne 'S') {
        Write-Host "Instalação abortada por falta de espaço." -ForegroundColor Yellow
        return
    }
}

if (-not $Mock -and -not $TargetDir) {
    Write-Host ""
    $confirm = Read-Host "Confirmar instalação em $TargetDrive ? [S/n]"
    if ($confirm -and $confirm.Trim().ToUpperInvariant() -eq 'N') {
        Write-Host "Instalação cancelada." -ForegroundColor Yellow
        return
    }
}

# ============================================================
# 4. Criação da Estrutura de Diretórios e Isolamento
# ============================================================
Write-Host ""
Write-Host "[3/3] Configurando estrutura Multi-Agent Portable..." -ForegroundColor Cyan

$dirProjetos = Join-Path $TargetDrive "Projetos"
$dirSkills   = Join-Path $TargetDrive "skills"
$dirConfig   = Join-Path $TargetDrive "config"
$dirBin      = Join-Path $TargetDrive "bin"
$dirData     = Join-Path $TargetDrive "data"

# Remove atributo oculto temporariamente caso já existam de instalação anterior
foreach ($hiddenDir in @($dirBin, $dirConfig, $dirData)) {
    if (Test-Path -LiteralPath $hiddenDir) {
        & attrib.exe -h $hiddenDir 2>$null
    }
}

foreach ($d in @($dirProjetos, $dirSkills, $dirConfig, $dirBin, $dirData)) {
    if (-not (Test-Path -LiteralPath $d)) {
        New-Item -ItemType Directory -Path $d -Force | Out-Null
    }
}

# Sincroniza skills compartilhadas
Write-Host "  -> Instalando skills compartilhadas em .\skills..." -ForegroundColor Gray
$sourceSkills = Join-Path $RepoRoot "skills"
if (Test-Path -LiteralPath $sourceSkills) {
    Get-ChildItem -LiteralPath $sourceSkills -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        $dstSkill = Join-Path $dirSkills $_.Name
        if (-not (Test-Path -LiteralPath $dstSkill)) {
            New-Item -ItemType Directory -Path $dstSkill -Force | Out-Null
        }
        Copy-Item -Path (Join-Path $_.FullName "*") -Destination $dstSkill -Recurse -Force
    }
} else {
    foreach ($fallbackSkill in @("diagnostico-windows", "diagnostico-impressora", "agent-desktop")) {
        $p = Join-Path $dirSkills $fallbackSkill
        if (-not (Test-Path -LiteralPath $p)) { New-Item -ItemType Directory -Path $p -Force | Out-Null }
    }
}

# Copia script de atualização inteligente para .\bin\update.ps1
$updateScriptSrc = Join-Path $RepoRoot "scripts\update.ps1"
if (Test-Path -LiteralPath $updateScriptSrc) {
    Copy-Item -LiteralPath $updateScriptSrc -Destination (Join-Path $dirBin "update.ps1") -Force
}

# Se estiver em modo Mock, compila um binário stub executável único para os agentes
$mockExeTemplate = $null
if ($Mock) {
    $mockExeTemplate = Join-Path $env:TEMP ("portable-mock-bin-" + [Guid]::NewGuid().ToString('N') + ".exe")
    New-MockBinary -OutExePath $mockExeTemplate
}

try {
    foreach ($agentId in $SelectedAgentIds) {
        $meta = $AgentCatalog[$agentId]
        Write-Host "  -> Configurando $($meta.DisplayName)..." -ForegroundColor Cyan

        # Diretório de dados isolado do agente
        $agentDataRoot = Join-Path $TargetDrive $meta.DataSubdir
        foreach ($sub in @('config', 'data', 'cache', 'state', 'tmp', 'appdata\Roaming', 'appdata\Local')) {
            $subPath = Join-Path $agentDataRoot $sub
            if (-not (Test-Path -LiteralPath $subPath)) {
                New-Item -ItemType Directory -Path $subPath -Force | Out-Null
            }
        }

        switch ($agentId) {
            1 {
                # 1. OpenCode Portable + MCP agent-desktop
                $homeDir = Join-Path $agentDataRoot "home"
                if (-not (Test-Path -LiteralPath $homeDir)) { New-Item -ItemType Directory -Path $homeDir -Force | Out-Null }

                $configJson = @'
{
  "$schema": "https://opencode.ai/config.json",
  "autoupdate": false,
  "share": "disabled",
  "mcp": {
    "agent-desktop": {
      "type": "local",
      "command": ["agent-desktop", "mcp"],
      "enabled": true
    }
  }
}
'@
                [System.IO.File]::WriteAllText((Join-Path $dirConfig "opencode.json"), $configJson)

                $targetOpencode = Join-Path $dirBin "opencode.exe"
                $targetAgentDesktop = Join-Path $dirBin "agent-desktop.exe"

                if ($Mock) {
                    Copy-Item -LiteralPath $mockExeTemplate -Destination $targetOpencode -Force
                    Copy-Item -LiteralPath $mockExeTemplate -Destination $targetAgentDesktop -Force
                } else {
                    $localOpencode = Join-Path $RepoRoot "bin\opencode.exe"
                    if (Test-Path -LiteralPath $localOpencode) {
                        Copy-Item -LiteralPath $localOpencode -Destination $targetOpencode -Force
                    } else {
                        Write-Host "     Baixando opencode.exe oficial do GitHub..." -ForegroundColor Gray
                        $tmpZip = Join-Path $env:TEMP ("opencode-dl-" + [Guid]::NewGuid().ToString('N') + ".zip")
                        $tmpDir = Join-Path $env:TEMP ("opencode-dl-" + [Guid]::NewGuid().ToString('N'))
                        try {
                            & curl.exe -fSL -o $tmpZip "https://github.com/anomalyco/opencode/releases/latest/download/opencode-windows-x64.zip"
                            Expand-Archive -LiteralPath $tmpZip -DestinationPath $tmpDir -Force
                            Copy-Item -LiteralPath (Join-Path $tmpDir "opencode.exe") -Destination $targetOpencode -Force
                        } finally {
                            if (Test-Path $tmpZip) { Remove-Item -Force $tmpZip -ErrorAction SilentlyContinue }
                            if (Test-Path $tmpDir) { Remove-Item -Recurse -Force $tmpDir -ErrorAction SilentlyContinue }
                        }
                    }

                    $sig = Get-AuthenticodeSignature $targetOpencode
                    if ($sig.Status -eq 'Valid') {
                        Write-Host "     [OK] Assinatura digital válida (Anomaly Innovations Inc.)." -ForegroundColor Green
                    } else {
                        Write-Host "     [AVISO] Status de assinatura do opencode.exe: $($sig.Status)" -ForegroundColor Yellow
                    }

                    $localAgentDesktop = Join-Path $RepoRoot "bin\agent-desktop.exe"
                    if (Test-Path -LiteralPath $localAgentDesktop) {
                        Copy-Item -LiteralPath $localAgentDesktop -Destination $targetAgentDesktop -Force
                    } else {
                        Write-Host "     Baixando agent-desktop (Vercel Labs)..." -ForegroundColor Gray
                        $tmpZip = Join-Path $env:TEMP ("agent-desktop-dl-" + [Guid]::NewGuid().ToString('N') + ".zip")
                        $tmpDir = Join-Path $env:TEMP ("agent-desktop-dl-" + [Guid]::NewGuid().ToString('N'))
                        try {
                            & curl.exe -fSL -o $tmpZip "https://github.com/vercel-labs/agent-desktop/releases/download/v1.2.0/agent-desktop-x86_64-pc-windows-msvc.zip"
                            Expand-Archive -LiteralPath $tmpZip -DestinationPath $tmpDir -Force
                            Copy-Item -LiteralPath (Join-Path $tmpDir "agent-desktop.exe") -Destination $targetAgentDesktop -Force
                        } finally {
                            if (Test-Path $tmpZip) { Remove-Item -Force $tmpZip -ErrorAction SilentlyContinue }
                            if (Test-Path $tmpDir) { Remove-Item -Recurse -Force $tmpDir -ErrorAction SilentlyContinue }
                        }
                    }
                }
            }

            2 {
                # 2. Claude Code Portable + Node.js standalone em .\bin\node\
                $claudeDotDir = Join-Path $agentDataRoot ".claude"
                $npmCacheDir  = Join-Path $agentDataRoot "npm-cache"
                foreach ($p in @($claudeDotDir, $npmCacheDir)) {
                    if (-not (Test-Path -LiteralPath $p)) { New-Item -ItemType Directory -Path $p -Force | Out-Null }
                }

                $nodeDir = Join-Path $dirBin "node"
                if (-not (Test-Path -LiteralPath $nodeDir)) {
                    New-Item -ItemType Directory -Path $nodeDir -Force | Out-Null
                }
                $targetNodeExe = Join-Path $nodeDir "node.exe"
                $targetClaudeCmd = Join-Path $nodeDir "claude.cmd"

                if ($Mock) {
                    Copy-Item -LiteralPath $mockExeTemplate -Destination $targetNodeExe -Force
                    $claudeShim = '@ECHO OFF' + "`r`n" + '"%~dp0node.exe" %*' + "`r`n"
                    [System.IO.File]::WriteAllText($targetClaudeCmd, $claudeShim)
                } else {
                    $localNodeDir = Join-Path $RepoRoot "bin\node"
                    if (Test-Path -LiteralPath (Join-Path $localNodeDir "node.exe")) {
                        Copy-Item -Path (Join-Path $localNodeDir "*") -Destination $nodeDir -Recurse -Force
                    } elseif (-not (Test-Path -LiteralPath $targetNodeExe)) {
                        Write-Host "     Baixando Node.js portátil (win-x64)..." -ForegroundColor Gray
                        $nodeVer = "v22.14.0"
                        $nodeUrl = "https://nodejs.org/dist/$nodeVer/node-$nodeVer-win-x64.zip"
                        $tmpZip = Join-Path $env:TEMP ("node-dl-" + [Guid]::NewGuid().ToString('N') + ".zip")
                        $tmpDir = Join-Path $env:TEMP ("node-dl-" + [Guid]::NewGuid().ToString('N'))
                        try {
                            & curl.exe -fSL -o $tmpZip $nodeUrl
                            Expand-Archive -LiteralPath $tmpZip -DestinationPath $tmpDir -Force
                            $extractedNodeFolder = Join-Path $tmpDir "node-$nodeVer-win-x64"
                            Copy-Item -Path (Join-Path $extractedNodeFolder "*") -Destination $nodeDir -Recurse -Force
                        } finally {
                            if (Test-Path $tmpZip) { Remove-Item -Force $tmpZip -ErrorAction SilentlyContinue }
                            if (Test-Path $tmpDir) { Remove-Item -Recurse -Force $tmpDir -ErrorAction SilentlyContinue }
                        }
                    }

                    $npmCmd = Join-Path $nodeDir "npm.cmd"
                    if ((Test-Path -LiteralPath $npmCmd) -and -not (Test-Path -LiteralPath $targetClaudeCmd)) {
                        Write-Host "     Instalando @anthropic-ai/claude-code no runtime portátil..." -ForegroundColor Gray
                        $prevPath = $env:PATH
                        try {
                            $env:PATH = "$nodeDir;$env:PATH"
                            & $npmCmd install -g "@anthropic-ai/claude-code" --prefix $nodeDir --cache $npmCacheDir --no-audit --no-fund
                        } finally {
                            $env:PATH = $prevPath
                        }
                    }
                }
            }

            3 {
                # 3. GitHub Copilot CLI (gh.exe portátil + extensão copilot)
                $extDir = Join-Path $agentDataRoot "extensions\gh-copilot"
                if (-not (Test-Path -LiteralPath $extDir)) {
                    New-Item -ItemType Directory -Path $extDir -Force | Out-Null
                }
                $ghCfgFile = Join-Path $agentDataRoot "config.yml"
                if (-not (Test-Path -LiteralPath $ghCfgFile)) {
                    [System.IO.File]::WriteAllText($ghCfgFile, "version: 1`r`ngit_protocol: https`r`n")
                }

                $targetGhExe = Join-Path $dirBin "gh.exe"
                if ($Mock) {
                    Copy-Item -LiteralPath $mockExeTemplate -Destination $targetGhExe -Force
                } else {
                    $localGh = Join-Path $RepoRoot "bin\gh.exe"
                    if (Test-Path -LiteralPath $localGh) {
                        Copy-Item -LiteralPath $localGh -Destination $targetGhExe -Force
                    } else {
                        Write-Host "     Baixando GitHub CLI (gh.exe) oficial..." -ForegroundColor Gray
                        $tmpZip = Join-Path $env:TEMP ("gh-dl-" + [Guid]::NewGuid().ToString('N') + ".zip")
                        $tmpDir = Join-Path $env:TEMP ("gh-dl-" + [Guid]::NewGuid().ToString('N'))
                        try {
                            $rawGh = & curl.exe -s https://api.github.com/repos/cli/cli/releases/latest
                            $mGh = [regex]::Match($rawGh, '"tag_name":\s*"v?([^"]+)"')
                            $ghVer = if ($mGh.Success) { $mGh.Groups[1].Value } else { "2.67.0" }
                            $ghUrl = "https://github.com/cli/cli/releases/download/v$ghVer/gh_${ghVer}_windows_amd64.zip"
                            & curl.exe -fSL -o $tmpZip $ghUrl
                            Expand-Archive -LiteralPath $tmpZip -DestinationPath $tmpDir -Force
                            $foundGh = Get-ChildItem -LiteralPath $tmpDir -Filter "gh.exe" -Recurse | Select-Object -First 1
                            if ($foundGh) {
                                Copy-Item -LiteralPath $foundGh.FullName -Destination $targetGhExe -Force
                            }
                        } finally {
                            if (Test-Path $tmpZip) { Remove-Item -Force $tmpZip -ErrorAction SilentlyContinue }
                            if (Test-Path $tmpDir) { Remove-Item -Recurse -Force $tmpDir -ErrorAction SilentlyContinue }
                        }
                    }
                }
            }

            4 {
                # 4. Antigravity CLI (Google DeepMind)
                $geminiDir = Join-Path $agentDataRoot ".gemini"
                if (-not (Test-Path -LiteralPath $geminiDir)) {
                    New-Item -ItemType Directory -Path $geminiDir -Force | Out-Null
                }

                $targetAgyExe = Join-Path $dirBin "antigravity.exe"
                $targetAgyCmd = Join-Path $dirBin "antigravity.cmd"

                if ($Mock) {
                    Copy-Item -LiteralPath $mockExeTemplate -Destination $targetAgyExe -Force
                    $agyShim = '@ECHO OFF' + "`r`n" + '"%~dp0antigravity.exe" %*' + "`r`n"
                    [System.IO.File]::WriteAllText($targetAgyCmd, $agyShim)
                } else {
                    $localAgyExe = Join-Path $RepoRoot "bin\antigravity.exe"
                    $localAgyCmd = Join-Path $RepoRoot "bin\antigravity.cmd"
                    if (Test-Path -LiteralPath $localAgyExe) {
                        Copy-Item -LiteralPath $localAgyExe -Destination $targetAgyExe -Force
                    } elseif (Test-Path -LiteralPath $localAgyCmd) {
                        Copy-Item -LiteralPath $localAgyCmd -Destination $targetAgyCmd -Force
                    } else {
                        $hostAgy = Get-Command antigravity.exe -ErrorAction SilentlyContinue
                        if (-not $hostAgy) { $hostAgy = Get-Command agy.exe -ErrorAction SilentlyContinue }
                        if ($hostAgy -and (Test-Path -LiteralPath $hostAgy.Source) -and ([System.IO.Path]::GetExtension($hostAgy.Source) -ieq '.exe')) {
                            Copy-Item -LiteralPath $hostAgy.Source -Destination $targetAgyExe -Force
                        }
                        $wrapper = @'
@ECHO OFF
IF EXIST "%~dp0antigravity.exe" (
  "%~dp0antigravity.exe" %*
  EXIT /B %ERRORLEVEL%
)
WHERE agy >NUL 2>&1
IF %ERRORLEVEL% EQU 0 (
  agy %*
  EXIT /B %ERRORLEVEL%
)
ECHO [antigravity-portable] Place antigravity.exe in .\bin\ or run update.ps1.
EXIT /B 1
'@
                        [System.IO.File]::WriteAllText($targetAgyCmd, $wrapper)
                    }
                }
            }
        }

        # Gera apenas o launcher correspondente ao agente selecionado
        $launcherPath = Join-Path $TargetDrive $meta.Launcher
        $launcherContent = New-LauncherContent -AgentId $agentId
        [System.IO.File]::WriteAllText($launcherPath, $launcherContent)
        Write-Host "     [OK] Launcher criado: $($meta.Launcher)" -ForegroundColor Green
    }
}
finally {
    if ($mockExeTemplate -and (Test-Path -LiteralPath $mockExeTemplate)) {
        Remove-Item -LiteralPath $mockExeTemplate -Force -ErrorAction SilentlyContinue
    }
}

# ============================================================
# 5. Ocultação de Pastas de Infraestrutura (attrib +h) e Unblock
# ============================================================
Write-Host "  -> Ocultando pastas de infraestrutura (bin, config, data)..." -ForegroundColor Gray
& attrib.exe +h $dirBin
& attrib.exe +h $dirConfig
& attrib.exe +h $dirData

Get-ChildItem -LiteralPath $TargetDrive -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object {
    Unblock-File -LiteralPath $_.FullName -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host "           INSTALAÇÃO CONCLUÍDA COM SUCESSO!                " -ForegroundColor White
Write-Host "============================================================" -ForegroundColor Green
Write-Host ""
Write-Host "Destino:              $TargetDrive" -ForegroundColor White
Write-Host "Agentes instalados:   $selectedNames" -ForegroundColor Cyan
Write-Host ""
Write-Host "Estrutura configurada:" -ForegroundColor Cyan
Write-Host "  $TargetDrive" -ForegroundColor White
Write-Host "  ├── 📁 Projetos/                 <- Workspace compartilhado" -ForegroundColor Gray
Write-Host "  ├── 📁 skills/                   <- Skills compartilhadas" -ForegroundColor Gray
foreach ($agentId in $SelectedAgentIds) {
    $launcherName = $AgentCatalog[$agentId].Launcher
    Write-Host "  ├── ⚙️ $launcherName" -ForegroundColor Yellow
}
Write-Host "  └── (Pastas ocultas +h: bin/, config/, data/)" -ForegroundColor DarkGray
Write-Host ""

if (-not $Mock -and -not $TargetDir) {
    Write-Host "Pressione qualquer tecla para finalizar..." -ForegroundColor Gray
    try {
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    } catch {
        $null = Read-Host
    }
}
