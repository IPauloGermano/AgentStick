param(
  [switch]$Force,
  [switch]$All,
  [switch]$Mock,
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$ExtraArgs
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$BinDir = Join-Path $Root 'bin'
$DataDir = Join-Path $Root 'data'

if ($ExtraArgs) {
  foreach ($arg in $ExtraArgs) {
    if ($arg -ieq '--all' -or $arg -ieq '-all') { $All = $true }
    if ($arg -ieq '--force' -or $arg -ieq '-force') { $Force = $true }
    if ($arg -ieq '--mock' -or $arg -ieq '-mock') { $Mock = $true }
  }
}

if (-not (Test-Path -LiteralPath $BinDir)) {
  New-Item -ItemType Directory -Path $BinDir -Force | Out-Null
}

$TargetOpencode     = Join-Path $BinDir 'opencode.exe'
$TargetAgentDesktop = Join-Path $BinDir 'agent-desktop.exe'
$TargetNodeDir      = Join-Path $BinDir 'node'
$TargetNodeExe      = Join-Path $TargetNodeDir 'node.exe'
$TargetClaudeCmd    = Join-Path $TargetNodeDir 'claude.cmd'
$TargetGhExe        = Join-Path $BinDir 'gh.exe'
$TargetAgyExe       = Join-Path $BinDir 'antigravity.exe'
$TargetAgyCmd       = Join-Path $BinDir 'antigravity.cmd'

$UpdateOpencode     = $All -or (Test-Path -LiteralPath $TargetOpencode)
$UpdateAgentDesktop = $All -or (Test-Path -LiteralPath $TargetAgentDesktop)
$UpdateClaude       = $All -or (Test-Path -LiteralPath $TargetNodeExe) -or (Test-Path -LiteralPath $TargetClaudeCmd)
$UpdateCopilot      = $All -or (Test-Path -LiteralPath $TargetGhExe)
$UpdateAntigravity  = $All -or (Test-Path -LiteralPath $TargetAgyExe) -or (Test-Path -LiteralPath $TargetAgyCmd)

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "       ATUALIZADOR INTELIGENTE MULTI-AGENT PORTABLE         " -ForegroundColor White
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""
if ($All) {
  Write-Host "Modo: --all (atualizando todos os agentes suportados)" -ForegroundColor Yellow
} else {
  Write-Host "Modo: Condicional (atualizando agentes presentes em .\bin\)" -ForegroundColor Gray
}
Write-Host ""

# ------------------------------------------------------------
# 1. OpenCode (Anomaly Innovations)
# ------------------------------------------------------------
if ($UpdateOpencode) {
  Write-Host "[OpenCode] Verificando versão do OpenCode..." -ForegroundColor Cyan
  if ($Mock) {
    Write-Host "  -> [MOCK] OpenCode verificado/atualizado em $TargetOpencode" -ForegroundColor Green
  } else {
    $tmpZip = $null
    $tmpExtract = $null
    try {
      $raw = & curl.exe -s https://api.github.com/repos/anomalyco/opencode/releases/latest
      $match = [regex]::Match($raw, '"tag_name":\s*"v?([^"]+)"')
      if (-not $match.Success) {
        Write-Host "[opencode] Não foi possível obter a versão mais recente via GitHub API." -ForegroundColor Yellow
      } else {
        $latestVersion = $match.Groups[1].Value
        $currentVersion = "desconhecida"
        if (Test-Path -LiteralPath $TargetOpencode) {
          $curOut = & $TargetOpencode --version 2>&1
          if ($curOut) { $currentVersion = ($curOut -split "`n")[0].Trim().TrimStart('v') }
        }

        Write-Host "  -> Versão atual:    $currentVersion"
        Write-Host "  -> Versão no GitHub: $latestVersion"

        if ($currentVersion -eq $latestVersion -and -not $Force) {
          Write-Host "  -> OpenCode já está na versão mais recente!" -ForegroundColor Green
        } else {
          $url = "https://github.com/anomalyco/opencode/releases/download/v$latestVersion/opencode-windows-x64.zip"
          $tmpZip = Join-Path $env:TEMP "opencode-update-$latestVersion.zip"
          $tmpExtract = Join-Path $env:TEMP "opencode-extract-$latestVersion"

          Write-Host "  -> Baixando v$latestVersion..." -ForegroundColor Cyan
          & curl.exe -fSL -o $tmpZip $url
          if ($LASTEXITCODE -ne 0 -or -not (Test-Path $tmpZip)) {
            throw "Falha no download de $url"
          }

          Write-Host "  -> Extraindo e validando assinatura digital..." -ForegroundColor Cyan
          if (Test-Path $tmpExtract) { Remove-Item -Recurse -Force $tmpExtract }
          Expand-Archive -LiteralPath $tmpZip -DestinationPath $tmpExtract -Force

          $newExe = Join-Path $tmpExtract 'opencode.exe'
          if (-not (Test-Path $newExe)) {
            throw "Arquivo opencode.exe não encontrado dentro do pacote baixado."
          }

          $sig = Get-AuthenticodeSignature $newExe
          if ($sig.Status -ne 'Valid') {
            throw "Assinatura digital do binário baixado não é válida ($($sig.Status)). Abortando por segurança!"
          }

          Write-Host "  -> Assinatura digital válida (Anomaly Innovations). Atualizando..." -ForegroundColor Green
          Copy-Item -LiteralPath $newExe -Destination $TargetOpencode -Force
          Unblock-File -Path $TargetOpencode -ErrorAction SilentlyContinue

          Write-Host "  -> Sucesso! OpenCode atualizado para v$latestVersion." -ForegroundColor Green
        }
      }
    }
    catch {
      Write-Host "[opencode] ERRO: $($_.Exception.Message)" -ForegroundColor Red
    }
    finally {
      if ($tmpZip -and (Test-Path $tmpZip)) { Remove-Item -Force $tmpZip -ErrorAction SilentlyContinue }
      if ($tmpExtract -and (Test-Path $tmpExtract)) { Remove-Item -Recurse -Force $tmpExtract -ErrorAction SilentlyContinue }
    }
  }
  Write-Host ""
}

# ------------------------------------------------------------
# 2. agent-desktop (Vercel Labs)
# ------------------------------------------------------------
if ($UpdateAgentDesktop) {
  Write-Host "[agent-desktop] Verificando versão do agent-desktop (MCP)..." -ForegroundColor Cyan
  if ($Mock) {
    Write-Host "  -> [MOCK] agent-desktop verificado/atualizado em $TargetAgentDesktop" -ForegroundColor Green
  } else {
    $tmpZipD = $null
    $tmpExtractD = $null
    try {
      $rawDesktop = & curl.exe -s https://api.github.com/repos/vercel-labs/agent-desktop/releases/latest
      $matchDesktop = [regex]::Match($rawDesktop, '"tag_name":\s*"v?([^"]+)"')
      if (-not $matchDesktop.Success) {
        Write-Host "[agent-desktop] Não foi possível obter a versão mais recente via GitHub API." -ForegroundColor Yellow
      } else {
        $latestDesktopVersion = $matchDesktop.Groups[1].Value
        $currentDesktopVersion = "desconhecida"
        if (Test-Path -LiteralPath $TargetAgentDesktop) {
          $curDOut = & $TargetAgentDesktop --version 2>&1
          if ($curDOut) {
            $firstLine = ($curDOut -split "`n")[0].Trim()
            $currentDesktopVersion = ($firstLine -replace '^agent-desktop\s*', '').TrimStart('v')
          }
        }

        Write-Host "  -> Versão atual:    $currentDesktopVersion"
        Write-Host "  -> Versão no GitHub: $latestDesktopVersion"

        if ($currentDesktopVersion -eq $latestDesktopVersion -and -not $Force) {
          Write-Host "  -> agent-desktop já está na versão mais recente!" -ForegroundColor Green
        } else {
          $urlDesktop = "https://github.com/vercel-labs/agent-desktop/releases/download/v$latestDesktopVersion/agent-desktop-x86_64-pc-windows-msvc.zip"
          $tmpZipD = Join-Path $env:TEMP "agent-desktop-update-$latestDesktopVersion.zip"
          $tmpExtractD = Join-Path $env:TEMP "agent-desktop-extract-$latestDesktopVersion"

          Write-Host "  -> Baixando v$latestDesktopVersion da Vercel Labs..." -ForegroundColor Cyan
          & curl.exe -fSL -o $tmpZipD $urlDesktop
          if ($LASTEXITCODE -ne 0 -or -not (Test-Path $tmpZipD)) {
            throw "Falha no download de $urlDesktop"
          }

          Write-Host "  -> Extraindo agent-desktop.exe..." -ForegroundColor Cyan
          if (Test-Path $tmpExtractD) { Remove-Item -Recurse -Force $tmpExtractD }
          Expand-Archive -LiteralPath $tmpZipD -DestinationPath $tmpExtractD -Force

          $newDesktopExe = Join-Path $tmpExtractD 'agent-desktop.exe'
          if (-not (Test-Path $newDesktopExe)) {
            throw "Arquivo agent-desktop.exe não encontrado dentro do pacote baixado."
          }

          Copy-Item -LiteralPath $newDesktopExe -Destination $TargetAgentDesktop -Force
          Unblock-File -Path $TargetAgentDesktop -ErrorAction SilentlyContinue

          Write-Host "  -> Sucesso! agent-desktop atualizado para v$latestDesktopVersion." -ForegroundColor Green
        }
      }
    }
    catch {
      Write-Host "[agent-desktop] ERRO: $($_.Exception.Message)" -ForegroundColor Red
    }
    finally {
      if ($tmpZipD -and (Test-Path $tmpZipD)) { Remove-Item -Force $tmpZipD -ErrorAction SilentlyContinue }
      if ($tmpExtractD -and (Test-Path $tmpExtractD)) { Remove-Item -Recurse -Force $tmpExtractD -ErrorAction SilentlyContinue }
    }
  }
  Write-Host ""
}

# ------------------------------------------------------------
# 3. Claude Code Portable (@anthropic-ai/claude-code)
# ------------------------------------------------------------
if ($UpdateClaude) {
  Write-Host "[Claude Code] Verificando atualização do Claude Code Portable..." -ForegroundColor Cyan
  if ($Mock) {
    Write-Host "  -> [MOCK] Claude Code verificado/atualizado em $TargetNodeDir" -ForegroundColor Green
  } else {
    try {
      $npmCmd = Join-Path $TargetNodeDir 'npm.cmd'
      $npmCache = Join-Path $DataDir 'claude\npm-cache'
      if (-not (Test-Path -LiteralPath $npmCache)) {
        New-Item -ItemType Directory -Path $npmCache -Force | Out-Null
      }
      if (Test-Path -LiteralPath $npmCmd) {
        $prevPath = $env:PATH
        try {
          $env:PATH = "$TargetNodeDir;$env:PATH"
          & $npmCmd install -g "@anthropic-ai/claude-code@latest" --prefix $TargetNodeDir --cache $npmCache --no-audit --no-fund
          Write-Host "  -> Sucesso! Claude Code atualizado no runtime portátil." -ForegroundColor Green
        } finally {
          $env:PATH = $prevPath
        }
      } else {
        Write-Host "  -> Runtime Node.js portátil não encontrado em $TargetNodeDir. Execute setup-pendrive.ps1 para instalar." -ForegroundColor Yellow
      }
    }
    catch {
      Write-Host "[claude-code] ERRO: $($_.Exception.Message)" -ForegroundColor Red
    }
  }
  Write-Host ""
}

# ------------------------------------------------------------
# 4. GitHub Copilot CLI (gh.exe)
# ------------------------------------------------------------
if ($UpdateCopilot) {
  Write-Host "[GitHub Copilot CLI] Verificando versão do GitHub CLI (gh.exe)..." -ForegroundColor Cyan
  if ($Mock) {
    Write-Host "  -> [MOCK] GitHub Copilot CLI verificado/atualizado em $TargetGhExe" -ForegroundColor Green
  } else {
    $tmpZipGh = $null
    $tmpExtractGh = $null
    try {
      $rawGh = & curl.exe -s https://api.github.com/repos/cli/cli/releases/latest
      $matchGh = [regex]::Match($rawGh, '"tag_name":\s*"v?([^"]+)"')
      if (-not $matchGh.Success) {
        Write-Host "[gh] Não foi possível obter a versão mais recente via GitHub API." -ForegroundColor Yellow
      } else {
        $latestGhVersion = $matchGh.Groups[1].Value
        $currentGhVersion = "desconhecida"
        if (Test-Path -LiteralPath $TargetGhExe) {
          $curGhOut = & $TargetGhExe --version 2>&1
          if ($curGhOut) {
            $mCur = [regex]::Match(($curGhOut -join ' '), 'gh version (\S+)')
            if ($mCur.Success) { $currentGhVersion = $mCur.Groups[1].Value }
          }
        }

        Write-Host "  -> Versão atual:    $currentGhVersion"
        Write-Host "  -> Versão no GitHub: $latestGhVersion"

        if ($currentGhVersion -eq $latestGhVersion -and -not $Force) {
          Write-Host "  -> gh.exe já está na versão mais recente!" -ForegroundColor Green
        } else {
          $urlGh = "https://github.com/cli/cli/releases/download/v$latestGhVersion/gh_${latestGhVersion}_windows_amd64.zip"
          $tmpZipGh = Join-Path $env:TEMP "gh-update-$latestGhVersion.zip"
          $tmpExtractGh = Join-Path $env:TEMP "gh-extract-$latestGhVersion"

          Write-Host "  -> Baixando gh v$latestGhVersion..." -ForegroundColor Cyan
          & curl.exe -fSL -o $tmpZipGh $urlGh
          if ($LASTEXITCODE -ne 0 -or -not (Test-Path $tmpZipGh)) {
            throw "Falha no download de $urlGh"
          }

          if (Test-Path $tmpExtractGh) { Remove-Item -Recurse -Force $tmpExtractGh }
          Expand-Archive -LiteralPath $tmpZipGh -DestinationPath $tmpExtractGh -Force

          $foundGh = Get-ChildItem -LiteralPath $tmpExtractGh -Filter "gh.exe" -Recurse | Select-Object -First 1
          if (-not $foundGh) {
            throw "Arquivo gh.exe não encontrado dentro do pacote baixado."
          }

          Copy-Item -LiteralPath $foundGh.FullName -Destination $TargetGhExe -Force
          Unblock-File -Path $TargetGhExe -ErrorAction SilentlyContinue
          Write-Host "  -> Sucesso! gh.exe atualizado para v$latestGhVersion." -ForegroundColor Green
        }
      }
    }
    catch {
      Write-Host "[gh] ERRO: $($_.Exception.Message)" -ForegroundColor Red
    }
    finally {
      if ($tmpZipGh -and (Test-Path $tmpZipGh)) { Remove-Item -Force $tmpZipGh -ErrorAction SilentlyContinue }
      if ($tmpExtractGh -and (Test-Path $tmpExtractGh)) { Remove-Item -Recurse -Force $tmpExtractGh -ErrorAction SilentlyContinue }
    }
  }
  Write-Host ""
}

# ------------------------------------------------------------
# 5. Antigravity CLI
# ------------------------------------------------------------
if ($UpdateAntigravity) {
  Write-Host "[Antigravity CLI] Verificando Antigravity CLI..." -ForegroundColor Cyan
  if ($Mock) {
    Write-Host "  -> [MOCK] Antigravity CLI verificado/atualizado em $BinDir" -ForegroundColor Green
  } else {
    $hostAgy = Get-Command antigravity.exe -ErrorAction SilentlyContinue
    if (-not $hostAgy) { $hostAgy = Get-Command agy.exe -ErrorAction SilentlyContinue }
    if ($hostAgy -and (Test-Path -LiteralPath $hostAgy.Source) -and ([System.IO.Path]::GetExtension($hostAgy.Source) -ieq '.exe')) {
      Copy-Item -LiteralPath $hostAgy.Source -Destination $TargetAgyExe -Force
      Write-Host "  -> Sucesso! Antigravity CLI sincronizado em $TargetAgyExe." -ForegroundColor Green
    } else {
      Write-Host "  -> Antigravity CLI mantido na versão portátil atual." -ForegroundColor Green
    }
  }
  Write-Host ""
}

if (-not ($UpdateOpencode -or $UpdateAgentDesktop -or $UpdateClaude -or $UpdateCopilot -or $UpdateAntigravity)) {
  Write-Host "Nenhum binário encontrado em .\bin\. Use --all para forçar o download de todos os agentes." -ForegroundColor Yellow
}

Write-Host "Verificação de atualizações concluída." -ForegroundColor Green
