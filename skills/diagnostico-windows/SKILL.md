---
name: diagnostico-windows
description: Executa rotinas de diagnóstico e suporte técnico para identificar e resolver problemas no Windows (hardware, rede, serviços, logs e integridade).
---

# Procedimentos de Diagnóstico e Suporte Windows

Esta skill orienta o agente a realizar diagnósticos estruturados, seguros e não destrutivos em computadores Windows.

## Diretrizes de Segurança (Crucial)
1. **Sempre diagnostique antes de alterar:** Nunca execute comandos que modifiquem o sistema (`Restart-Service`, `Stop-Process`, `Set-ItemProperty`, `Remove-Item`) sem antes inspecionar o estado atual.
2. **Peça confirmação para ações de impacto:** Reiniciar computadores, apagar arquivos ou alterar o Registro (`regedit`) exige confirmação clara do usuário.
3. **Não execute comandos destrutivos:** Evite `format`, `del /s`, `rmdir /s` em pastas do sistema sem escopo estrito.

---

## 1. Verificação Rápida de Recursos (CPU, RAM, Disco)
Quando o usuário relatar lentidão ou travamentos:
```powershell
# 1. Informações básicas de hardware e tempo ligado (uptime)
Get-CimInstance Win32_OperatingSystem | Select-Object Caption, OSArchitecture, LastBootUpTime, TotalVisibleMemorySize, FreePhysicalMemory

# 2. Espaço em todos os discos
Get-Volume | Where-Object DriveType -eq 'Fixed' | Select-Object DriveLetter, FileSystemLabel, @{N='FreeGB';E={[math]::Round($_.SizeRemaining/1GB, 2)}}, @{N='TotalGB';E={[math]::Round($_.Size/1GB, 2)}}

# 3. Processos consumindo mais CPU e Memória
Get-Process | Sort-Object CPU -Descending | Select-Object -First 8 Name, Id, CPU, WorkingSet64
```

---

## 2. Diagnóstico de Rede e Conectividade
Quando houver falha de internet, lentidão ou rede inacessível:
```powershell
# 1. Adaptadores e endereços IP
Get-NetIPConfiguration | Select-Object InterfaceAlias, IPv4Address, IPv4DefaultGateway, DNSServer

# 2. Testar conectividade externa básica
Test-NetConnection -ComputerName 8.8.8.8 -InformationLevel Detailed

# 3. Testar resolução de nomes (DNS)
Resolve-DnsName google.com

# 4. Limpar cache DNS (se suspeitar de DNS corrompido)
Clear-DnsClientCache
```

---

## 3. Inspeção de Falhas nos Logs do Windows (Event Viewer)
Identificar erros críticos nas últimas 24 horas:
```powershell
# Erros do Sistema (Windows / Hardware / Drivers)
Get-WinEvent -FilterHashtable @{LogName='System'; Level=1,2; StartTime=(Get-Date).AddDays(-1)} -MaxEvents 15 -ErrorAction SilentlyContinue |
  Select-Object TimeCreated, Id, ProviderName, Message

# Erros de Aplicativos (Crashes de software)
Get-WinEvent -FilterHashtable @{LogName='Application'; Level=1,2; StartTime=(Get-Date).AddDays(-1)} -MaxEvents 15 -ErrorAction SilentlyContinue |
  Select-Object TimeCreated, Id, ProviderName, Message
```

---

## 4. Diagnóstico de Serviços Essenciais
Verificar se serviços críticos do Windows estão parados:
```powershell
# Serviços que deveriam iniciar automaticamente mas estão parados
Get-Service | Where-Object { $_.StartType -eq 'Automatic' -and $_.Status -ne 'Running' } |
  Select-Object Name, DisplayName, Status
```

---

## 5. Integridade do Sistema Operacional (Avançado)
Se arquivos do sistema estiverem corrompidos:
* Recomende rodar no terminal com privilégios de Administrador:
  ```powershell
  sfc /scannow
  DISM /Online /Cleanup-Image /RestoreHealth
  ```
