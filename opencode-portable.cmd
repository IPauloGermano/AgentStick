@ECHO OFF
TITLE OpenCode Portable
SETLOCAL

IF "%~1"=="" (
  ECHO.
  ECHO  =======================================================
  ECHO    OpenCode Portable
  ECHO    Initializing environment, skills, and tools...
  ECHO    Please wait a moment...
  ECHO  =======================================================
  ECHO.
)
REM ============================================================
REM  Opencode Portable launcher (Windows)
REM  Config, dati, cache e log restano dentro la cartella
REM  portable (.\data). Niente in %USERPROFILE%\.config o
REM  %USERPROFILE%\.local\share.
REM ============================================================

REM Cartella che contiene questo script (senza backslash finale: "D:\" diventa
REM "D:", così "%ROOT%\data" diventa sempre "D:\data" senza doppia barra "D:\\data"
REM che fa fallire LoadLibrary di Bun/OpenTUI con error code 126).
SET "ROOT=%~dp0"
IF "%ROOT:~-1%"=="\" SET "ROOT=%ROOT:~0,-1%"

IF /I "%~1"=="--update" GOTO :doupdate
IF /I "%~1"=="--atualizar" GOTO :doupdate

SET "HOST_TMP=%TEMP%"
SET "DATA=%ROOT%\data"
IF NOT EXIST "%DATA%\config" MKDIR "%DATA%\config"
IF NOT EXIST "%DATA%\data"   MKDIR "%DATA%\data"
IF NOT EXIST "%DATA%\cache"  MKDIR "%DATA%\cache"
IF NOT EXIST "%DATA%\state"  MKDIR "%DATA%\state"
SET "TMPROOT=%DATA%\tmp"
IF /I NOT "%~d0"=="%SystemDrive%" IF DEFINED HOST_TMP SET "TMPROOT=%HOST_TMP%\opencode-portable-tmp"
IF NOT EXIST "%TMPROOT%" MKDIR "%TMPROOT%"

REM Prima esecuzione: crea config da template se manca (fresh clone)
IF NOT EXIST "%ROOT%\config\opencode.json" IF EXIST "%ROOT%\config\opencode.example.json" COPY /Y "%ROOT%\config\opencode.example.json" "%ROOT%\config\opencode.json" >NUL

REM Redirect di config / dati / cache dentro .\data
SET "XDG_CONFIG_HOME=%DATA%\config"
SET "XDG_DATA_HOME=%DATA%\data"
SET "XDG_CACHE_HOME=%DATA%\cache"
SET "XDG_STATE_HOME=%DATA%\state"
SET "OPENCODE_CONFIG=%ROOT%\config\opencode.json"
REM Niente fetch bloccante di models.dev all'avvio (10-30s): usa cache/integrato
SET "OPENCODE_DISABLE_MODELS_FETCH=1"
IF EXIST "%ROOT%\bin" SET "PATH=%ROOT%\bin;%PATH%"

REM Portable skills: sincronizza le skills portatili nella configurazione di sessione
SET "SKILLS_SRC=%ROOT%\skills"
IF NOT EXIST "%SKILLS_SRC%" SET "SKILLS_SRC=%ROOT%\.opencode\skills"
IF EXIST "%SKILLS_SRC%" (
  IF NOT EXIST "%DATA%\config\opencode\skills" MKDIR "%DATA%\config\opencode\skills" 2>NUL
  XCOPY "%SKILLS_SRC%" "%DATA%\config\opencode\skills" /E /I /Y /Q >NUL 2>&1
)

REM Foto della temp di sistema PRIMA del redirect (guard: cancello solo cio che nasce in questa run)
SET "SYS_TMP=%TEMP%"
SET "SYS_OPENC=%SYS_TMP%\opencode"
IF EXIST "%SYS_OPENC%" (SET "SYS_OPENC_EXISTS=1") ELSE (SET "SYS_OPENC_EXISTS=0")
SET "SYS_LOCAL_OPENC=%LOCALAPPDATA%\opencode"
IF EXIST "%SYS_LOCAL_OPENC%" (SET "SYS_LOCAL_EXISTS=1") ELSE (SET "SYS_LOCAL_EXISTS=0")
SET "SYS_ROAM_OPENC=%APPDATA%\opencode"
IF EXIST "%SYS_ROAM_OPENC%" (SET "SYS_ROAM_EXISTS=1") ELSE (SET "SYS_ROAM_EXISTS=0")
REM Fallback auth di opencode quando XDG_DATA_HOME manca (~/.opencode/auth.json):
REM lo impostiamo sempre, ma un figlio che ignora i redirect potrebbe scriverci.
SET "SYS_HOME_OPENC=%USERPROFILE%\.opencode"
IF EXIST "%SYS_HOME_OPENC%" (SET "SYS_HOME_EXISTS=1") ELSE (SET "SYS_HOME_EXISTS=0")

REM Risoluzione binario PRIMA di creare tmp: le uscite anticipate (binario
REM mancante) non lasciano directory temporanee.
REM EXE bundled. Fallback a opencode da PATH SOLO con opt-in esplicito
REM (--from-path ovunque tra gli argomenti, o OPENCODE_ALLOW_PATH_FALLBACK=1):
REM senza opt-in un eseguibile omonimo nel PATH verrebbe lanciato in silenzio.
SET "BIN=%ROOT%\bin\opencode.exe"
SET "ALLOW_PATH=0"
IF /I "%OPENCODE_ALLOW_PATH_FALLBACK%"=="1" SET "ALLOW_PATH=1"
REM Ricostruisci gli argomenti togliendo --from-path (ovunque sia): SHIFT non
REM tocca %*, quindi %* inoltrerebbe il flag al figlio. Re-quoting uniforme.
REM NOTA fedeltà: metacaratteri grezzi (& | ^) e stringhe vuote negli argomenti
REM CLI possono alterarsi/troncarsi in transito (limite di cmd.exe, non aggirabile
REM in puro batch); per argomenti esotici usare opencode-portable.ps1 (exact).
SET "FWD="
:argloop
IF "%~1"=="" GOTO :argdone
IF "%~1"=="--from-path" (SET "ALLOW_PATH=1" & SHIFT /1 & GOTO :argloop)
SET "FWD=%FWD% "%~1""
SHIFT /1
GOTO :argloop
:argdone
IF EXIST "%BIN%" GOTO :runbin
IF "%ALLOW_PATH%"=="0" (
  ECHO [opencode-portable] ERROR: "%BIN%" not found.
  ECHO [opencode-portable] Run scripts\setup.ps1 to download it, or reuse opencode from PATH with --from-path or OPENCODE_ALLOW_PATH_FALLBACK=1.
  ENDLOCAL & EXIT /B 1
)
WHERE opencode >NUL 2>&1
IF ERRORLEVEL 1 (
  ECHO [opencode-portable] ERROR: no opencode found in PATH.
  ENDLOCAL & EXIT /B 1
)
SET "BIN_FROM_PATH="
FOR /F "delims=" %%B IN ('WHERE opencode 2^>NUL') DO IF NOT DEFINED BIN_FROM_PATH SET "BIN_FROM_PATH=%%B"
IF NOT DEFINED BIN_FROM_PATH (
  ECHO [opencode-portable] ERROR: unable to resolve opencode in PATH.
  ENDLOCAL & EXIT /B 1
)
SET "BIN=%BIN_FROM_PATH%"
ECHO [opencode-portable] WARNING: using opencode from PATH: "%BIN%"
:runbin

REM Temp isolata per questa run (sicura anche con istanze concorrenti).
REM NOTA: %TIME% dipende dal locale (separatori diversi, spazi): sanitizza.
SET "RAWTIME=%TIME: =0%"
SET "RAWTIME=%RAWTIME:/=-%"
SET "RAWTIME=%RAWTIME:.=-%"
SET "RAWTIME=%RAWTIME:,=-%"
SET "RAWTIME=%RAWTIME:;=-%"
SET "RUNID=run-%RAWTIME:~0,2%%RAWTIME:~3,2%%RAWTIME:~6,2%%RAWTIME:~9,2%-%RANDOM%"
SET "RUN_TMP=%TMPROOT%\%RUNID%"
IF EXIST "%RUN_TMP%" SET "RUN_TMP=%TMPROOT%\%RUNID%-%RANDOM%"
IF EXIST "%RUN_TMP%" SET "RUN_TMP=%TMPROOT%\%RUNID%-%RANDOM%-%RANDOM%"
MKDIR "%RUN_TMP%" 2>NUL
SET "CLEAN_RUN_TMP=1"
IF NOT EXIST "%RUN_TMP%" SET "CLEAN_RUN_TMP=0"
IF "%CLEAN_RUN_TMP%"=="0" SET "RUN_TMP=%TMPROOT%"
REM Marchio di proprietà: solo le tmp con questo file vengono spazzate sotto.
REM Senza, lo sweeper per età non distinguerebbe le tmp vive degli altri
REM launcher (ps1/sh usano lo stesso prefisso run-*).
IF "%CLEAN_RUN_TMP%"=="1" TYPE NUL > "%RUN_TMP%\.portable-cmd" 2>NUL

REM Foto della tmp del portable (guard: opencode potrebbe scriverci una cartella "opencode")
SET "TMPROOT_OPENC=%TMPROOT%\opencode"
IF EXIST "%TMPROOT_OPENC%" (SET "TMPROOT_OPENC_EXISTS=1") ELSE (SET "TMPROOT_OPENC_EXISTS=0")

REM Sweeper: tmp di run morte da oltre 7 giorni (crash/kill). NOTA: cmd non
REM conosce il PID (niente liveness check come ps1/sh/exe): cancella solo le
REM dir col marchio .portable-cmd creato sopra, così non tocca mai le tmp
REM vive degli altri launcher. Resta la soglia di 7 giorni per non toccare
REM run recenti/concorrenti; una sessione cmd viva da oltre 7 giorni resta
REM un caso non supportato (usare ps1/exe per sessioni lunghissime).
FORFILES /P "%TMPROOT%" /M "run-*" /D -7 /C "CMD /C IF @isdir==TRUE IF EXIST \"%TMPROOT%\@fname\.portable-cmd\" RMDIR /S /Q @path" 2>NUL

REM Temp di opencode e processi figli nella tmp di questa run
SET "TMP=%RUN_TMP%"
SET "TEMP=%RUN_TMP%"
SET "TMPDIR=%RUN_TMP%"

REM Esegui il figlio. CALL per .cmd/.bat (senza, il controllo non torna e la
REM cleanup sotto non gira mai). Delayed expansion solo in questo blocco: così
REM i metacaratteri già quotati in FWD non vengono reinterpretati in uscita.
REM Inicia dentro de Projetos caso nenhum argumento tenha sido passado
IF "%~1"=="" IF EXIST "%ROOT%\Projetos" CD /D "%ROOT%\Projetos"

CALL :checkdb
IF /I "%BIN:~-4%"==".cmd" GOTO :runcmd
IF /I "%BIN:~-4%"==".bat" GOTO :runcmd
SETLOCAL EnableDelayedExpansion
"!BIN!" !FWD!
SET "EXITCODE=!ERRORLEVEL!"
ENDLOCAL & SET "EXITCODE=%EXITCODE%"
GOTO :afterrun
:runcmd
SETLOCAL EnableDelayedExpansion
CALL "!BIN!" !FWD!
SET "EXITCODE=!ERRORLEVEL!"
ENDLOCAL & SET "EXITCODE=%EXITCODE%"
GOTO :afterrun
:afterrun
REM Cleanup best-effort della sola tmp di questa run (mai il codice d'uscita).
REM Retry breve: il runtime Bun mappa una sua DLL in TMPDIR e Defender scansiona
REM i file nuovi; un singolo RMDIR perderebbe la race contro questi lock
REM transitori. Fino a ~10s, poi i resti vanno allo sweeper al prossimo avvio.
SET "MARKER_CHECK=%RUN_TMP:\data\tmp\run-=%"
IF "%CLEAN_RUN_TMP%"=="1" IF NOT "%MARKER_CHECK%"=="%RUN_TMP%" IF EXIST "%RUN_TMP%" CALL :delretry "%RUN_TMP%"
IF "%TMPROOT_OPENC_EXISTS%"=="0" IF EXIST "%TMPROOT_OPENC%" RMDIR /S /Q "%TMPROOT_OPENC%" 2>NUL
REM Cartelle opencode fuori dal portable: solo se generate da questa run
REM (RMDIR per le dir, DEL per gli eventuali file: mirror di DeletePath)
REM Cartelle opencode fuori dal portable: solo se generate da questa run.
REM RMDIR per le dir (test via suffisso \NUL), DEL per i file: mirror di DeletePath.
IF DEFINED SYS_TMP IF "%SYS_OPENC_EXISTS%"=="0" IF EXIST "%SYS_OPENC%\NUL" (RMDIR /S /Q "%SYS_OPENC%" 2>NUL) ELSE IF EXIST "%SYS_OPENC%" DEL /F /Q "%SYS_OPENC%" 2>NUL
IF DEFINED LOCALAPPDATA IF "%SYS_LOCAL_EXISTS%"=="0" IF EXIST "%SYS_LOCAL_OPENC%\NUL" (RMDIR /S /Q "%SYS_LOCAL_OPENC%" 2>NUL) ELSE IF EXIST "%SYS_LOCAL_OPENC%" DEL /F /Q "%SYS_LOCAL_OPENC%" 2>NUL
IF DEFINED APPDATA IF "%SYS_ROAM_EXISTS%"=="0" IF EXIST "%SYS_ROAM_OPENC%\NUL" (RMDIR /S /Q "%SYS_ROAM_OPENC%" 2>NUL) ELSE IF EXIST "%SYS_ROAM_OPENC%" DEL /F /Q "%SYS_ROAM_OPENC%" 2>NUL
IF DEFINED USERPROFILE IF "%SYS_HOME_EXISTS%"=="0" IF EXIST "%SYS_HOME_OPENC%\NUL" (RMDIR /S /Q "%SYS_HOME_OPENC%" 2>NUL) ELSE IF EXIST "%SYS_HOME_OPENC%" DEL /F /Q "%SYS_HOME_OPENC%" 2>NUL
IF NOT "%EXITCODE%"=="0" IF "%~1"=="" (
  ECHO.
  ECHO [opencode-portable] Process exited with code %EXITCODE%.
  IF EXIST "%DATA%\data\opencode\log" ECHO [opencode-portable] Logs: "%DATA%\data\opencode\log"
  ECHO Press any key to close this window...
  PAUSE >NUL
)
ENDLOCAL & EXIT /B %EXITCODE%

:checkdb
SET "OPENCODE_DB=%DATA%\data\opencode\opencode.db"
IF NOT EXIST "%OPENCODE_DB%" GOTO :EOF
IF NOT EXIST "%OPENCODE_DB%-wal" IF NOT EXIST "%OPENCODE_DB%-shm" GOTO :EOF

SET "SQLITE_BIN="
SET "SQLITE_IS_CMD=0"
IF EXIST "%ROOT%\bin\sqlite3.cmd" (
  SET "SQLITE_BIN=%ROOT%\bin\sqlite3.cmd"
  SET "SQLITE_IS_CMD=1"
) ELSE IF EXIST "%ROOT%\bin\sqlite3.exe" (
  SET "SQLITE_BIN=%ROOT%\bin\sqlite3.exe"
)
IF NOT DEFINED SQLITE_BIN GOTO :EOF

TASKLIST /FI "IMAGENAME eq opencode.exe" 2>NUL | FIND /I "opencode.exe" >NUL
IF %ERRORLEVEL% EQU 0 GOTO :EOF

CALL :walcheckpoint
IF %ERRORLEVEL% EQU 0 GOTO :checkdb_cleanup

IF NOT EXIST "%OPENCODE_DB%-shm" GOTO :wal_recover
DEL /F /Q "%OPENCODE_DB%-shm" 2>NUL
CALL :walcheckpoint
IF %ERRORLEVEL% EQU 0 GOTO :checkdb_cleanup

:wal_recover
ECHO [opencode-portable] WARNING: SQLite WAL checkpoint failed. Backing up and recovering database...
SET "DB_BAK=%OPENCODE_DB%.bak"
COPY /Y "%OPENCODE_DB%" "%DB_BAK%" >NUL 2>&1
IF NOT %ERRORLEVEL% EQU 0 (
  ECHO [opencode-portable] ERROR: Failed to back up "%OPENCODE_DB%". Check free space on drive %~d0.
  GOTO :checkdb_cleanup
)
IF EXIST "%OPENCODE_DB%-wal" COPY /Y "%OPENCODE_DB%-wal" "%DB_BAK%-wal" >NUL 2>&1

IF EXIST "%OPENCODE_DB%-wal" DEL /F /Q "%OPENCODE_DB%-wal" 2>NUL
IF EXIST "%OPENCODE_DB%-shm" DEL /F /Q "%OPENCODE_DB%-shm" 2>NUL

CALL :checkdbintegrity "%OPENCODE_DB%"
IF %ERRORLEVEL% EQU 0 (
  ECHO [opencode-portable] Database recovered by clearing corrupt WAL/SHM ^(backup: "%DB_BAK%"^).
  GOTO :checkdb_cleanup
)

IF EXIST "%OPENCODE_DB%.recovered" DEL /F /Q "%OPENCODE_DB%.recovered" 2>NUL
CALL :runsqlite_out "%OPENCODE_DB%" ".recover" "%RUN_TMP%\opencode-recover.sql"
IF NOT %ERRORLEVEL% EQU 0 GOTO :recover_fail
IF NOT EXIST "%RUN_TMP%\opencode-recover.sql" GOTO :recover_fail
CALL :runsqlite_in "%OPENCODE_DB%.recovered" "%RUN_TMP%\opencode-recover.sql"
IF NOT %ERRORLEVEL% EQU 0 GOTO :recover_fail
IF NOT EXIST "%OPENCODE_DB%.recovered" GOTO :recover_fail
CALL :checkdbintegrity "%OPENCODE_DB%.recovered"
IF NOT %ERRORLEVEL% EQU 0 GOTO :recover_fail
MOVE /Y "%OPENCODE_DB%.recovered" "%OPENCODE_DB%" >NUL 2>&1
IF NOT %ERRORLEVEL% EQU 0 GOTO :recover_fail
ECHO [opencode-portable] Database reconstructed with sqlite3 .recover ^(backup: "%DB_BAK%"^).
GOTO :checkdb_cleanup

:recover_fail
IF EXIST "%OPENCODE_DB%.recovered" DEL /F /Q "%OPENCODE_DB%.recovered" 2>NUL
ECHO [opencode-portable] WARNING: Automatic database recovery did not complete. Backup at "%DB_BAK%".

:checkdb_cleanup
DEL /F /Q "%RUN_TMP%\walcheck.txt" "%RUN_TMP%\dbcheck.txt" "%RUN_TMP%\opencode-recover.sql" 2>NUL
GOTO :EOF

:walcheckpoint
DEL /F /Q "%RUN_TMP%\walcheck.txt" 2>NUL
CALL :runsqlite_out "%OPENCODE_DB%" "PRAGMA busy_timeout=3000; PRAGMA wal_checkpoint(TRUNCATE);" "%RUN_TMP%\walcheck.txt"
IF NOT %ERRORLEVEL% EQU 0 EXIT /B 1
FINDSTR /B "1|" "%RUN_TMP%\walcheck.txt" >NUL 2>&1
IF %ERRORLEVEL% EQU 0 EXIT /B 1
EXIT /B 0

:checkdbintegrity
DEL /F /Q "%RUN_TMP%\dbcheck.txt" 2>NUL
CALL :runsqlite_out "%~1" "PRAGMA quick_check;" "%RUN_TMP%\dbcheck.txt"
IF NOT %ERRORLEVEL% EQU 0 EXIT /B 1
FINDSTR /X /I "ok" "%RUN_TMP%\dbcheck.txt" >NUL 2>&1
EXIT /B %ERRORLEVEL%

:runsqlite_out
IF "%SQLITE_IS_CMD%"=="1" GOTO :runsqlite_out_cmd
"%SQLITE_BIN%" "%~1" "%~2" > "%~3" 2>NUL
EXIT /B %ERRORLEVEL%
:runsqlite_out_cmd
CALL "%SQLITE_BIN%" "%~1" "%~2" > "%~3" 2>NUL
EXIT /B %ERRORLEVEL%

:runsqlite_in
IF "%SQLITE_IS_CMD%"=="1" GOTO :runsqlite_in_cmd
"%SQLITE_BIN%" "%~1" < "%~2" >NUL 2>&1
EXIT /B %ERRORLEVEL%
:runsqlite_in_cmd
CALL "%SQLITE_BIN%" "%~1" < "%~2" >NUL 2>&1
EXIT /B %ERRORLEVEL%

REM Sottoroutine di cancellazione con retry (chiamata solo da sopra, mai in
REM caduta libera: dopo EXIT non si torna). Non tocca mai EXITCODE.
:delretry
FOR /L %%R IN (1,1,10) DO (
  IF NOT EXIST "%~1" GOTO :EOF
  RMDIR /S /Q "%~1" 2>NUL
  IF NOT EXIST "%~1" GOTO :EOF
  REM Pausa ~1s senza dipendere da stdin/console: timeout.exe fallisce con
  REM input ridirezionato (uso pipato, CI), mentre ping su loopback no.
  ping -n 2 127.0.0.1 >NUL 2>&1
)
GOTO :EOF

:doupdate
powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\bin\update.ps1"
ECHO.
ECHO Press any key to exit...
PAUSE >NUL
EXIT /B %ERRORLEVEL%
