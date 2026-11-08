---
name: diagnostico-impressora
description: Guia interativo para diagnosticar e solucionar problemas com impressoras no Windows. Faz perguntas ao usuário sobre modelo, tipo de conexão e sintomas, lista impressoras disponíveis e pede confirmações antes de ações destrutivas.
---

# Procedimentos de Diagnóstico e Suporte Interativo a Impressoras (Windows)

Esta skill orienta o agente a agir como um **técnico de suporte nível 2 amigável e interativo**. O agente **NUNCA deve sair executando alterações no escuro**: ele deve interagir com o usuário, fazer perguntas claras e confirmar ações.

---

## 💬 Fluxo de Atendimento Interativo (Passo a Passo)

### 1. Descoberta Inicial e Seleção da Impressora
Se o usuário apenas disser algo genérico como *"a impressora não funciona"* ou *"estou com problema na impressora"*:
1. Execute rapidamente:
   ```powershell
   Get-Printer | Select-Object Name, DriverName, PortName, PrinterStatus, JobCount, WorkOffline | Format-Table -AutoSize
   ```
2. **Pergunte interativamente ao usuário:**
   > *"Encontrei as seguintes impressoras instaladas neste computador:*
   > *(Lista das impressoras encontradas com seus respectivos status)*
   > **Com qual dessas impressoras você está tendo problemas? (Ou informe a marca/modelo caso ela não esteja aparecendo na lista)**"*

### 2. Identificação do Tipo de Conexão e Sintoma
Se o usuário informar o nome ou modelo:
1. **Pergunte o sintoma principal:**
   - *A impressora aparece como "Offline"?*
   - *O documento fica em "Excluindo..." ou "Erro - Imprimindo" e a fila travou?*
   - *O computador manda imprimir, mas a impressora nem pisca a luz/nem reage?*
   - *Ela é ligada via Cabo USB no computador ou via Cabo de Rede / Wi-Fi?*
2. Se for **Impressora de Rede / Wi-Fi** e ela estiver inacessível:
   > *"Você sabe o endereço IP fixo dela ou consegue ver o IP no visor/painel da impressora?"*

### 3. Confirmação Obrigatória Antes de Limpar Fila
Se a fila estiver travada com documentos:
1. Mostre os documentos presos:
   ```powershell
   Get-PrintJob -PrinterName "<NomeDaImpressora>" | Select-Object Id, DocumentName, JobStatus, TotalPages, SubmittedTime
   ```
2. **Pergunte antes de apagar:**
   > *"Existem **X documento(s)** travados na fila de impressão. Para destravar o serviço, preciso cancelar esses documentos e reiniciar o Spooler. **Posso prosseguir e limpar a fila, ou há algum documento que você prefere tentar salvar antes?**"*

### 4. Validação Final com Página de Teste
Após aplicar qualquer correção:
1. **Pergunte:**
   > *"A fila foi liberada e o status normalizado. **Deseja que eu dispare uma página de teste do Windows agora para confirmar se ela imprime?**"*

---

## 🛠️ Comandos de Diagnóstico e Correção

### 🔍 1. Listar Impressoras e Status Atual
```powershell
Get-Printer | Select-Object Name, DriverName, PortName, PrinterStatus, JobCount, WorkOffline, Default | Format-Table -AutoSize
```

---

### 📄 2. Inspecionar Fila de Impressão
```powershell
Get-PrintJob -PrinterName "<NomeDaImpressora>" |
    Select-Object Id, DocumentName, JobStatus, Owner, TotalPages, SubmittedTime | Format-Table -AutoSize
```

Se o usuário autorizar cancelar um documento específico:
```powershell
Remove-PrintJob -PrinterName "<NomeDaImpressora>" -ID <ID_Do_Job>
```

---

### ⚙️ 3. Reset Completo da Fila e do Spooler (Após Confirmação)
Use quando houver documentos presos em "Excluindo..." que o Windows não cancela pela interface gráfica:
```powershell
# 1. Parar o serviço Spooler
Stop-Service -Name Spooler -Force

# 2. Apagar os arquivos de spool (.SHD e .SPL)
Remove-Item -Path "$env:SystemRoot\System32\spool\PRINTERS\*" -Force -ErrorAction SilentlyContinue

# 3. Reiniciar o Spooler
Start-Service -Name Spooler

# 4. Checar status
Get-Service -Name Spooler
```

---

### 🌐 4. Testes de Rede (Impressoras de Rede/Wi-Fi)
Para impressoras conectadas via rede ou quando o usuário fornecer o IP:

```powershell
$printerIP = "<IP_DA_IMPRESSORA>"

# Teste 1: Ping básico
Test-Connection -ComputerName $printerIP -Count 2

# Teste 2: Porta padrão RAW 9100 (usada por 95% das impressoras de rede)
Test-NetConnection -ComputerName $printerIP -Port 9100

# Teste 3: Painel Web de administração da impressora
Test-NetConnection -ComputerName $printerIP -Port 80
```
> Se o Ping responder mas a porta 9100 falhar, o serviço de impressão da impressora pode ter travado (recomende desligar da tomada por 30s).  
> Se o Ping falhar, o IP da impressora mudou por DHCP ou o cabo/Wi-Fi caiu.

---

### ⚠️ 5. Detecção de Porta WSD (Causa de "Offline" Fantasma)
Muitas impressoras que ficam "Offline" no Windows 10/11 estão configuradas em portas `WSD`:
```powershell
Get-Printer | Where-Object { $_.PortName -like "WSD*" } | Select-Object Name, PortName, WorkOffline
```

Se estiver Offline:
```powershell
# Forçar retorno ao status Online
Set-Printer -Name "<NomeDaImpressora>" -WorkOffline $false
```
> **Orientação técnica para o usuário:** Se a impressora WSD vive caindo, recomende criar uma porta TCP/IP padrão com o IP fixo da impressora.

---

### 🔌 6. Impressoras USB (Cabo Local)
Inspecione se o Windows reconhece o dispositivo físico na porta USB:
```powershell
Get-PnpDevice -Class 'PrintQueue', 'Printer', 'USB' |
    Where-Object { $_.FriendlyName -like "*Print*" -or $_.Class -in @('PrintQueue','Printer') } |
    Select-Object FriendlyName, Status, Problem, ProblemDescription | Format-Table -AutoSize
```
> Se o status for `Error` ou `Problem`, oriente o usuário a trocar a porta USB ou testar outro cabo.

---

### 🖨️ 7. Disparar Página de Teste do Windows
Quando o usuário concordar em testar:
```powershell
$p = Get-CimInstance Win32_Printer -Filter "Name = '<NomeDaImpressora>'"
Invoke-CimMethod -InputObject $p -MethodName PrintTestPage
```
