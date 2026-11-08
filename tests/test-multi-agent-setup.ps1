#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Suíte de testes automatizados para o Instalador Multi-Agent Portátil.
.DESCRIPTION
    Valida sem necessidade de pendrive físico:
      1. Mock de instalação seletiva (ex: 1,3) e completa (1,2,3,4 / 5), cálculo de espaço livre e pastas ocultas (+h).
      2. Isolamento estrito de variáveis de ambiente (nenhum vazamento para %USERPROFILE% ou %APPDATA% fora do mock),
         banner em inglês, inicialização em .\Projetos, repasse de argumentos (%*) e tratamento de erro.
      3. Integridade do pacote (scripts/pack-release.ps1 com scanner de segredos e $Include atualizado)
         e compilação limpa (dotnet build src/OpencodePortable/OpencodePortable.csproj com 0 erros e 0 avisos).
#>

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent $PSScriptRoot
$SetupScript = Join-Path $RepoRoot "scripts\setup-pendrive.ps1"
$PackScript  = Join-Path $RepoRoot "scripts\pack-release.ps1"
$CsprojPath  = Join-Path $RepoRoot "src\OpencodePortable\OpencodePortable.csproj"

$env:PORTABLE_NONINTERACTIVE = '1'
$Passed = 0

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) {
        throw "[FALHA NO TESTE] $Message"
    }
    $script:Passed++
    Write-Host "  [PASS] $Message" -ForegroundColor Green
}

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "   SUÍTE DE TESTES AUTOMATIZADOS - MULTI-AGENT PORTABLE     " -ForegroundColor White
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

$MockDrive       = Join-Path $env:TEMP "mock-usb-test"
$MockSubsetDrive = Join-Path $env:TEMP "mock-usb-subset-test"
$TempPackOut     = Join-Path $env:TEMP ("mock-pack-dist-" + [Guid]::NewGuid().ToString('N'))

try {
    # Limpeza prévia caso existam de execuções anteriores
    foreach ($dir in @($MockDrive, $MockSubsetDrive, $TempPackOut)) {
        if (Test-Path -LiteralPath $dir) {
            Get-ChildItem -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object {
                if ($_.Attributes -band [System.IO.FileAttributes]::Hidden) {
                    $_.Attributes = $_.Attributes -bxor [System.IO.FileAttributes]::Hidden
                }
            }
            Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    # ============================================================
    # 1. Teste de Mock de Instalação (Seletiva, Espaço e Completa)
    # ============================================================
    Write-Host "[1/3] Executando Testes de Mock de Instalação..." -ForegroundColor Yellow

    # 1a. Teste de seleção parcial (-Agents 1,3)
    & $SetupScript -Mock -TargetDir $MockSubsetDrive -Agents 1,3 | Out-Null
    Assert-True (Test-Path -LiteralPath (Join-Path $MockSubsetDrive "Iniciar OpenCode.bat")) "Seleção parcial (1,3) criou 'Iniciar OpenCode.bat'"
    Assert-True (Test-Path -LiteralPath (Join-Path $MockSubsetDrive "Iniciar Copilot.bat")) "Seleção parcial (1,3) criou 'Iniciar Copilot.bat'"
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $MockSubsetDrive "Iniciar Claude Code.bat"))) "Seleção parcial (1,3) NÃO criou 'Iniciar Claude Code.bat'"
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $MockSubsetDrive "Iniciar Antigravity.bat"))) "Seleção parcial (1,3) NÃO criou 'Iniciar Antigravity.bat'"

    # 1b. Teste de bloqueio de espaço insuficiente
    $spaceBlocked = $false
    try {
        & $SetupScript -Mock -TargetDir $MockSubsetDrive -Agents 5 -SimulatedFreeSpace 10MB | Out-Null
    } catch {
        $spaceBlocked = $true
    }
    Assert-True $spaceBlocked "Cálculo de espaço livre aborta quando espaço disponível é insuficiente"

    # 1c. Instalação completa (-Mock -TargetDir $MockDrive -Agents 1,2,3,4)
    & $SetupScript -Mock -TargetDir $MockDrive -Agents 1,2,3,4 | Out-Null

    Assert-True (Test-Path -LiteralPath (Join-Path $MockDrive "Projetos")) "Pasta visível 'Projetos' criada em $MockDrive"
    Assert-True (Test-Path -LiteralPath (Join-Path $MockDrive "skills\diagnostico-windows\SKILL.md")) "Skill 'diagnostico-windows' sincronizada em .\skills"
    Assert-True (Test-Path -LiteralPath (Join-Path $MockDrive "skills\diagnostico-impressora\SKILL.md")) "Skill 'diagnostico-impressora' sincronizada em .\skills"
    Assert-True (Test-Path -LiteralPath (Join-Path $MockDrive "skills\agent-desktop\SKILL.md")) "Skill 'agent-desktop' sincronizada em .\skills"

    foreach ($hiddenName in @('bin', 'config', 'data')) {
        $hiddenPath = Join-Path $MockDrive $hiddenName
        Assert-True (Test-Path -LiteralPath $hiddenPath) "Pasta de infraestrutura '$hiddenName' existe"
        $item = Get-Item -LiteralPath $hiddenPath -Force
        $isHidden = ($item.Attributes -band [System.IO.FileAttributes]::Hidden) -ne 0
        Assert-True $isHidden "Pasta '$hiddenName' está configurada com atributo oculto (+h)"
    }

    $expectedLaunchers = @(
        'Iniciar OpenCode.bat',
        'Iniciar Claude Code.bat',
        'Iniciar Copilot.bat',
        'Iniciar Antigravity.bat'
    )
    foreach ($l in $expectedLaunchers) {
        Assert-True (Test-Path -LiteralPath (Join-Path $MockDrive $l)) "Launcher '$l' criado na raiz do mock drive"
    }

    Write-Host ""

    # ============================================================
    # 2. Teste de Isolamento de Variáveis de Ambiente e Launchers
    # ============================================================
    Write-Host "[2/3] Executando Testes de Isolamento de Variáveis de Ambiente..." -ForegroundColor Yellow

    $LauncherSpecs = @(
        @{
            File        = 'Iniciar OpenCode.bat'
            BannerTitle = 'OpenCode Portable'
            DataSubdir  = 'data\opencode'
            ExtraVar    = 'OPENCODE_CONFIG'
            ExtraPrefix = (Join-Path $MockDrive 'config\opencode.json')
        },
        @{
            File        = 'Iniciar Claude Code.bat'
            BannerTitle = 'Claude Code Portable'
            DataSubdir  = 'data\claude'
            ExtraVar    = 'CLAUDE_CONFIG_DIR'
            ExtraPrefix = (Join-Path $MockDrive 'data\claude\.claude')
        },
        @{
            File        = 'Iniciar Copilot.bat'
            BannerTitle = 'GitHub Copilot CLI Portable'
            DataSubdir  = 'data\gh'
            ExtraVar    = 'GH_CONFIG_DIR'
            ExtraPrefix = (Join-Path $MockDrive 'data\gh')
        },
        @{
            File        = 'Iniciar Antigravity.bat'
            BannerTitle = 'Antigravity CLI Portable'
            DataSubdir  = 'data\antigravity'
            ExtraVar    = 'GEMINI_HOME'
            ExtraPrefix = (Join-Path $MockDrive 'data\antigravity\.gemini')
        }
    )

    foreach ($spec in $LauncherSpecs) {
        $batPath = Join-Path $MockDrive $spec.File
        $expectedDataDir = Join-Path $MockDrive $spec.DataSubdir
        $expectedProjetos = Join-Path $MockDrive 'Projetos'

        # 2a. Executa o binário mock real através do launcher com repasse de argumentos (%*)
        $outLines = & cmd.exe /c "`"$batPath`" --custom-arg-check" 2>&1
        $exitCode = $LASTEXITCODE
        $outText  = ($outLines | ForEach-Object { [string]$_ }) -join "`n"

        Assert-True ($exitCode -eq 0) "$($spec.File) executou com código de saída 0"
        Assert-True ($outText -match [regex]::Escape($spec.BannerTitle)) "$($spec.File) exibiu o título '$($spec.BannerTitle)' no banner"
        Assert-True ($outText -match "Initializing environment, skills, and tools\.\.\.") "$($spec.File) exibiu o banner em inglês"
        Assert-True ($outText -match "--custom-arg-check") "$($spec.File) repassou argumentos de linha de comando (%*) ao processo filho"

        # Parseia todas as linhas KEY=VALUE emitidas pelo processo filho dentro do ambiente isolado
        $envMap = @{}
        foreach ($line in $outLines) {
            $s = [string]$line
            if ($s -match '^([A-Z_]+)=(.*)$') {
                $envMap[$Matches[1]] = $Matches[2].Trim()
            }
        }

        Assert-True ($envMap['CWD'] -ieq $expectedProjetos) "$($spec.File) iniciou a sessão dentro de .\Projetos ($($envMap['CWD']))"

        $isolatedVars = @(
            'USERPROFILE', 'HOME', 'APPDATA', 'LOCALAPPDATA',
            'XDG_CONFIG_HOME', 'XDG_DATA_HOME', 'XDG_CACHE_HOME', 'XDG_STATE_HOME',
            'TMP', 'TEMP', 'TMPDIR'
        )
        foreach ($varName in $isolatedVars) {
            $val = $envMap[$varName]
            $insideMock = (-not [string]::IsNullOrWhiteSpace($val)) -and $val.StartsWith($expectedDataDir, [StringComparison]::OrdinalIgnoreCase)
            Assert-True $insideMock "$($spec.File): $varName isolado dentro de $($spec.DataSubdir) ($val)"
        }

        $extraVarName = $spec.ExtraVar
        $extraVal = $envMap[$extraVarName]
        $extraOk = (-not [string]::IsNullOrWhiteSpace($extraVal)) -and $extraVal.StartsWith($spec.ExtraPrefix, [StringComparison]::OrdinalIgnoreCase)
        Assert-True $extraOk "$($spec.File): $extraVarName isolado corretamente ($extraVal)"

        # Verifica limpeza da pasta temporária run-* após encerramento
        $leftoverRuns = @(Get-ChildItem -LiteralPath (Join-Path $expectedDataDir 'tmp') -Filter 'run-*' -Directory -ErrorAction SilentlyContinue)
        Assert-True ($leftoverRuns.Count -eq 0) "$($spec.File) limpou o diretório temporário da sessão ao sair"

        # 2b. Testa tratamento de erro (código de saída != 0)
        $failLines = & cmd.exe /c "`"$batPath`" --test-fail" 2>&1
        $failCode  = $LASTEXITCODE
        $failText  = ($failLines | ForEach-Object { [string]$_ }) -join "`n"
        Assert-True ($failCode -ne 0) "$($spec.File) propagou código de erro ($failCode) ao falhar"
        Assert-True ($failText -match "Process exited with code" -and $failText -match "Press any key to close this window") "$($spec.File) exibiu mensagem de erro padrão em inglês"
    }

    # 2c. Teste do atualizador inteligente (update.ps1 condicional e --all)
    $installedUpdater = Join-Path $MockDrive "bin\update.ps1"
    $updOut = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $installedUpdater --all --mock 2>&1
    Assert-True ($LASTEXITCODE -eq 0) "Atualizador inteligente (update.ps1 --all --mock) executou com código 0"

    Write-Host ""

    # ============================================================
    # 3. Validação de Portabilidade e Integridade do Pacote
    # ============================================================
    Write-Host "[3/3] Validando Portabilidade, Scanner de Segredos e Build C#..." -ForegroundColor Yellow

    $packContent = Get-Content -LiteralPath $PackScript -Raw
    Assert-True ($packContent -match "instalar-pendrive\.bat") "scripts/pack-release.ps1 contém 'instalar-pendrive.bat' em `$Include"
    Assert-True ($packContent -match "'tests'") "scripts/pack-release.ps1 contém 'tests' em `$Include"

    & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $PackScript -Out $TempPackOut | Out-Null
    Assert-True ($LASTEXITCODE -eq 0) "scripts/pack-release.ps1 passou no scanner de segredos com código 0"
    Assert-True (Test-Path -LiteralPath (Join-Path $TempPackOut "opencode-portable-win-x64.zip")) "Pacote opencode-portable-win-x64.zip gerado com sucesso"

    $buildLines = & dotnet build $CsprojPath --nologo 2>&1
    $buildExit  = $LASTEXITCODE
    $buildText  = ($buildLines | ForEach-Object { [string]$_ }) -join "`n"
    Assert-True ($buildExit -eq 0) "dotnet build src/OpencodePortable/OpencodePortable.csproj concluiu com código 0"
    $zeroWarnings = ($buildText -match "0 Warning\(s\)" -or $buildText -match "0 Aviso\(s\)")
    $zeroErrors   = ($buildText -match "0 Error\(s\)" -or $buildText -match "0 Erro\(s\)")
    Assert-True ($zeroWarnings -and $zeroErrors) "dotnet build concluiu com 0 erros e 0 avisos"

    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Green
    Write-Host "  TODOS OS $Passed TESTES PASSARAM COM SUCESSO!             " -ForegroundColor White
    Write-Host "============================================================" -ForegroundColor Green
    exit 0
}
finally {
    foreach ($dir in @($MockDrive, $MockSubsetDrive, $TempPackOut)) {
        if (Test-Path -LiteralPath $dir) {
            Get-ChildItem -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object {
                if ($_.Attributes -band [System.IO.FileAttributes]::Hidden) {
                    $_.Attributes = $_.Attributes -bxor [System.IO.FileAttributes]::Hidden
                }
            }
            Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
