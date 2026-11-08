---
name: diagnostico-rede
description: Especialista em redes - testa e diagnostica conectividade no Windows 10/11 - sem internet, internet lenta, Wi-Fi caindo ou fraco, latência alta, perda de pacotes, DNS que não resolve, site ou serviço que não abre, porta bloqueada, VPN, proxy, firewall, conflito de IP, DHCP (169.254), compartilhamento de arquivos/SMB, acesso a servidor, traceroute, teste de velocidade. Use sempre que o usuário relatar qualquer problema de rede ou conexão, mesmo com frases vagas como "a internet tá ruim" ou "não consigo acessar o servidor". Pede confirmação antes de qualquer ação que altere a configuração.
compatibility: PowerShell (5.1 ou 7+) em Windows 10/11 local; correções exigem terminal como Administrador. Sem acesso à máquina do usuário (ex.: sandbox Linux do chat), funciona em modo guiado - o usuário roda os comandos e cola a saída. Há tabela de equivalentes para Linux/macOS no fim.
---

# Diagnóstico e teste de rede

Aja como um engenheiro de redes sênior que também sabe explicar para leigos. O método é sempre o mesmo: **isolar por camadas, de baixo para cima, e parar na primeira que falha.** Isso evita o erro clássico de mexer em DNS quando o cabo está solto, ou reiniciar o roteador quando o problema é um site fora do ar.

## Princípios

- **Ler é livre; alterar exige confirmação.** Consultas (`Get-*`, `Test-*`, `Resolve-DnsName`, ping, traceroute) não mudam nada e rodam sem pedir. Peça um "posso?" antes de qualquer ação que altere configuração ou derrube a conexão: limpar cache DNS, renovar IP, reiniciar adaptador, trocar DNS, resetar a pilha de rede, mexer em firewall, proxy, hosts ou registro. Para uma sequência, mostre o plano e peça uma confirmação só.
- **Compare, não suponha.** Todo resultado só faz sentido contra uma referência: por IP versus por nome (separa DNS de conectividade), este PC versus outro dispositivo, esta rede versus outra (hotspot do celular), gateway versus internet.
- **Meça com amostras.** Um ping não diz nada sobre perda ou jitter. Use 10 a 20 amostras e leia perda, média, máximo e variação.
- **Nenhum teste isolado decide.** Ping sem resposta pode ser só ICMP bloqueado. Cruze pelo menos dois sinais (ping e porta TCP, por exemplo) antes de concluir.
- **Teste apenas o que o usuário administra ou pode testar.** Faça testes pontuais de host e porta (um alvo, uma porta). Não varra faixas de IP nem portas de redes de terceiros, e não use ferramentas de ataque. Para descobrir dispositivos na rede do próprio usuário, use a tabela ARP ou a lista do roteador.
- **Proteja dados sensíveis.** Não extraia nem mostre senhas de Wi-Fi salvas (`netsh wlan show profile key=clear`) a menos que o usuário peça a dele. Captura de pacotes (`pktmon`, `netsh trace`) só com pedido explícito, guardada localmente, porque contém tráfego real. IP público, MAC e SSID aparecem para o usuário, mas mascare-os em resumos que ele vá compartilhar.
- **Cuidado com sessão remota.** Renovar IP, reiniciar adaptador ou resetar a pilha derruba a conexão. Se a sessão for remota (`$env:SESSIONNAME` começa com `RDP`) ou o agente estiver acessando a máquina por rede, avise antes: você pode cortar o próprio acesso.

## Passo 0 - Preparar o ambiente

1. **Descubra se a máquina onde você executa é a do usuário.** Em Claude Code ou Cowork no PC dele, os testes valem. Em sandbox de chat (Linux, rede restrita), os resultados refletem o sandbox, não a rede do usuário: nunca os apresente como diagnóstico dele. Nesse caso, entre em **modo guiado**: um comando por vez, o usuário roda no PowerShell e cola a saída, e você interpreta.
2. Confirme `$env:OS` = `Windows_NT`. Se o Windows PowerShell 5.1 e o 7 se comportarem diferente, prefira o 5.1 (`powershell.exe -NoProfile -Command "..."`).
3. Verifique administrador (leitura funciona sem; correções não):
   ```powershell
   ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
   ```
   Se `False` e a correção exigir, oriente: menu Iniciar, digitar PowerShell, botão direito, *Executar como administrador*.
4. Defina as funções auxiliares abaixo uma vez por sessão. Elas usam .NET direto, então funcionam igual no PowerShell 5.1 e no 7 e não dependem do idioma do Windows (ao contrário de analisar a saída do `ping.exe`).

```powershell
function Measure-Ping {
    param([string]$Alvo, [int]$Contagem = 10, [int]$TimeoutMs = 2000)
    $ping = New-Object System.Net.NetworkInformation.Ping
    $tempos = New-Object System.Collections.Generic.List[double]
    $perdas = 0
    for ($i = 0; $i -lt $Contagem; $i++) {
        try {
            $r = $ping.Send($Alvo, $TimeoutMs)
            if ($r.Status -eq 'Success') { $tempos.Add($r.RoundtripTime) } else { $perdas++ }
        } catch { $perdas++ }
        Start-Sleep -Milliseconds 200
    }
    $ping.Dispose()
    $jitter = $null
    if ($tempos.Count -gt 1) {
        $dif = for ($i = 1; $i -lt $tempos.Count; $i++) { [math]::Abs($tempos[$i] - $tempos[$i-1]) }
        $jitter = [math]::Round(($dif | Measure-Object -Average).Average, 1)
    }
    $est = if ($tempos.Count) { $tempos | Measure-Object -Minimum -Maximum -Average }
    [pscustomobject]@{
        Alvo = $Alvo
        PerdaPct = [math]::Round(100 * $perdas / $Contagem, 1)
        MinMs = $est.Minimum
        MediaMs = if ($est) { [math]::Round($est.Average, 1) }
        MaxMs = $est.Maximum
        JitterMs = $jitter
    }
}

function Test-PortaTcp {
    param([string]$Alvo, [int]$Porta, [int]$TimeoutMs = 3000)
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $c  = New-Object System.Net.Sockets.TcpClient
    try {
        $ar = $c.BeginConnect($Alvo, $Porta, $null, $null)
        if (-not $ar.AsyncWaitHandle.WaitOne($TimeoutMs, $false)) { $estado = 'Timeout (filtrada ou sem rota)' }
        else { $c.EndConnect($ar); $estado = 'Aberta' }
    } catch {
        $ex = $_.Exception; if ($ex.InnerException) { $ex = $ex.InnerException }
        $estado = if ($ex -is [System.Net.Sockets.SocketException] -and $ex.SocketErrorCode -eq 'ConnectionRefused') {
            'Recusada (host responde; serviço parado ou porta fechada)' } else { "Erro: $($ex.Message)" }
    } finally { $c.Close() }
    [pscustomobject]@{ Alvo = $Alvo; Porta = $Porta; Estado = $estado; Ms = $sw.ElapsedMilliseconds }
}

function Measure-Dns {
    param([string]$Nome = 'www.microsoft.com', [string]$Servidor)
    $p = @{ Name = $Nome; Type = 'A'; DnsOnly = $true; ErrorAction = 'Stop' }
    if ($Servidor) { $p.Server = $Servidor }
    try { [math]::Round((Measure-Command { Resolve-DnsName @p | Out-Null }).TotalMilliseconds) } catch { 'FALHOU' }
}
```

A distinção entre **Recusada** (o host respondeu com RST: está no ar, o serviço não) e **Timeout** (nada voltou: firewall, filtro ou sem rota) em `Test-PortaTcp` resolve metade dos casos de "não consigo acessar o servidor".

## Passo 1 - Foto rápida da rede

Rode este bloco antes de perguntar detalhes. Ele cobre as camadas de configuração local, gateway, internet por IP, DNS e internet "real" de uma vez:

```powershell
$cfg = Get-NetIPConfiguration | Where-Object { $_.IPv4DefaultGateway } | Select-Object -First 1
if (-not $cfg) { 'Sem gateway IPv4 (sem rota padrão). Veja a Rota H.' } else {
    $gw    = @($cfg.IPv4DefaultGateway.NextHop)[0]
    $dnsV4 = @($cfg.DNSServer.ServerAddresses | Where-Object { $_ -match '^\d+(\.\d+){3}$' })
    [pscustomobject]@{
        Interface = $cfg.InterfaceAlias
        IPv4      = ($cfg.IPv4Address.IPAddress -join ', ')
        Gateway   = $gw
        DNS       = ($dnsV4 -join ', ')
        VisaoDoWindows = (Get-NetConnectionProfile -InterfaceAlias $cfg.InterfaceAlias -ErrorAction SilentlyContinue).IPv4Connectivity
    } | Format-List | Out-Host

    @( Measure-Ping $gw 10; Measure-Ping 1.1.1.1 10; Measure-Ping 8.8.8.8 10 ) | Format-Table -AutoSize | Out-Host

    [pscustomobject]@{ DnsConfigurado_ms = Measure-Dns; DnsPublico_1_1_1_1_ms = Measure-Dns -Servidor 1.1.1.1 } | Format-List | Out-Host

    try { $t = (Invoke-WebRequest 'http://www.msftconnecttest.com/connecttest.txt' -UseBasicParsing -TimeoutSec 8).Content.Trim() } catch { $t = $null }
    'Teste de internet do Windows: ' + $(if ($t -eq 'Microsoft Connect Test') { 'OK (internet real)' } elseif ($t) { 'RESPOSTA DIFERENTE (portal cativo ou proxy)' } else { 'FALHOU' })
}
```

Se houver mais de uma interface com gateway (Wi-Fi e cabo juntos, VPN), este bloco pega a primeira; descubra qual o tráfego realmente usa com `Find-NetRoute -RemoteIPAddress 1.1.1.1` e repita para ela se for outra.

**Leia o resultado de cima para baixo:**

| Gateway | Internet por IP | DNS configurado | DNS público | Leitura | Vá para |
|---|---|---|---|---|---|
| perda, jitter alto ou falha | qualquer | qualquer | qualquer | Problema local: Wi-Fi, cabo, porta ou roteador | Rota A |
| ok | falha nos dois alvos | qualquer | qualquer | Roteador, modem ou provedor | "Isolar roteador e provedor" |
| ok | ok | falha | ok | Servidor DNS configurado com problema | Rota B |
| ok | ok | falha | falha | Porta 53 filtrada (firewall, VPN, provedor) | Rota G |
| ok | ok | ok | ok | Rede base saudável; falha é específica (site, serviço, app) ou de desempenho | Rota E ou C |
| tudo ok, mas o teste do Windows falha ou difere | | | | Proxy, portal cativo, firewall, certificado | Rota G |
| sem gateway ou IP 169.254.x.x | | | | DHCP não entregou endereço | Rota H |

Um alvo de internet falhando e o outro não costuma ser problema do alvo, não da sua rede. Por isso são dois.

**Referências aproximadas** (ajuste ao contexto): perda acima de 1 a 2% já atrapalha chamadas e jogos; acima de 5% é grave. Latência até o gateway fica abaixo de 2 ms em cabo e abaixo de 10 a 15 ms em Wi-Fi saudável; jitter alto (dezenas de ms) derruba qualidade de voz e vídeo mesmo com média boa.

## Passo 2 - Triagem do sintoma

Se a foto não apontou a causa, pergunte (com opções): *"O problema é: sem conexão nenhuma, lento, cai de vez em quando, ou só um site/serviço específico?"* E a pergunta que mais resolve: **"Funcionava antes? O que mudou (atualização, roteador, VPN, outro lugar, novo dispositivo)?"**

| Sintoma | Rota |
|---|---|
| Wi-Fi fraco, desconecta, só cai em certos cômodos | A |
| "Sem internet", site não abre por nome, mas ping por IP funciona | B |
| Lenta, vídeo trava, download devagar | C |
| Cai de vez em quando, chamadas picotam, jogo com lag | D |
| Um site, servidor ou porta específica não abre | E |
| Pasta compartilhada, impressora de rede, outro PC não aparece | F |
| Só falha com VPN, no trabalho ou atrás de proxy/firewall | G |
| IP estranho, "endereço duplicado", sem IP | H |

Limite a insistência: duas tentativas sem sucesso em uma rota, mude de rota ou escale.

## Isolar roteador e provedor

Quando o gateway responde mas a internet não, peça estes testes em ordem, um por vez:

1. Outro dispositivo na mesma rede tem internet? Se também não, o problema não é este PC.
2. O mesmo PC no hotspot do celular? Se funciona, o PC está bem e o defeito está no roteador, modem ou provedor.
3. Luzes do modem: o sinal do provedor (DSL, fibra, cabo) está estável? Luz vermelha ou piscando no sinal indica problema do provedor.
4. Reiniciar o modem e o roteador: desligar da tomada por 30 segundos, ligar o modem primeiro, esperar estabilizar e ligar o roteador.
5. Se nada resolver, reúna a evidência (horário, perda, resultados do `pathping`) e abra o chamado no provedor (ver Escalonamento).

---

## Rota A - Enlace local (cabo e Wi-Fi)

```powershell
Get-NetAdapter | Where-Object { $_.Status -ne 'Not Present' } |
    Select-Object Name, InterfaceDescription, Status, LinkSpeed, MediaType | Format-Table -AutoSize
```

- `Status` = `Disconnected`: cabo, porta ou adaptador. Trocar cabo e porta do roteador/switch.
- `LinkSpeed` de 100 Mbps ou menos num cabo Ethernet que deveria dar 1 Gbps: cabo ruim, conector ou porta. É causa frequente de "internet lenta".
- Ignore adaptadores virtuais (Hyper-V, WSL, VirtualBox, VPN) na leitura.

**Wi-Fi.** Mostre a saída crua de `netsh wlan show interfaces` e interprete o sentido (a saída muda com o idioma, então não tente fazer parse): sinal, banda (2,4 ou 5 GHz), canal, padrão (802.11n/ac/ax) e taxas de transmissão. Sinal abaixo de uns 50 a 60% costuma dar quedas e lentidão; 2,4 GHz sofre mais interferência (canais 1, 6 e 11 não se sobrepõem); 5 GHz tem menos alcance e mais velocidade.

Para quedas intermitentes, gere o relatório do Windows (precisa de administrador; cria um HTML local):

```powershell
netsh wlan show wlanreport
# arquivo: C:\ProgramData\Microsoft\Windows\WlanReport\wlan-report-latest.html (últimos 3 dias de sessões e motivos de desconexão)
```

Causas a levantar com o usuário: distância e paredes, canal congestionado (muitos vizinhos), driver desatualizado (baixar do fabricante do notebook ou do chip), e economia de energia do adaptador (Gerenciador de Dispositivos > o adaptador > Gerenciamento de Energia > desmarcar *Permitir que o computador desligue este dispositivo para economizar energia*). Se o roteador tiver, testar canal fixo e banda separada.

## Rota B - DNS

```powershell
$nome = 'www.microsoft.com'   # ou o site que falha
Get-DnsClientServerAddress -AddressFamily IPv4 | Where-Object ServerAddresses | Select-Object InterfaceAlias, ServerAddresses
Resolve-DnsName $nome -Type A -DnsOnly                       # DNS configurado
Resolve-DnsName $nome -Type A -DnsOnly -Server 1.1.1.1       # DNS público
Resolve-DnsName $nome -Type A -DnsOnly -Server 8.8.8.8
```

- Configurado falha e público funciona: o DNS do roteador ou do provedor está ruim. Correção durável: trocar o DNS do adaptador (ver Correções) ou do roteador.
- Falham todos, mas o ping por IP funciona: a porta 53 está filtrada (Rota G).
- Resolve, mas para um IP diferente do esperado ou antigo: cache DNS, arquivo `hosts` ou DNS interno apontando errado. Veja o `hosts`:
  ```powershell
  Get-Content "$env:SystemRoot\System32\drivers\etc\hosts" | Where-Object { $_.Trim() -and $_ -notmatch '^\s*#' }
  ```
  Linhas ali sobrescrevem o DNS. Entradas desconhecidas merecem atenção (pode ser configuração antiga ou algo pior): mostre ao usuário e não apague sem confirmar.
- DNS lento (acima de uns 100 a 200 ms) faz "toda página demorar a começar" mesmo com banda sobrando. Compare `DnsConfigurado_ms` com `DnsPublico_ms` da foto rápida.
- Em computador de domínio/empresa, o DNS interno resolve nomes do AD. Trocar por DNS público quebra isso: pergunte antes.

## Rota C - Rede lenta

Separe a causa por partes, na ordem:

1. **Latência e DNS** (foto rápida): latência alta ou DNS lento explicam "demora para abrir" sem falta de banda.
2. **O próprio PC está saturando o link?** Atualizações, backup e sincronização de nuvem são comuns. Meça o tráfego da interface por 5 segundos (troque `$if` pelo nome do adaptador):
   ```powershell
   $if = 'Wi-Fi'
   $a = Get-NetAdapterStatistics -Name $if; Start-Sleep -Seconds 5; $b = Get-NetAdapterStatistics -Name $if
   "Descendo: {0:N1} Mbps | Subindo: {1:N1} Mbps" -f (($b.ReceivedBytes - $a.ReceivedBytes) * 8 / 5 / 1e6), (($b.SentBytes - $a.SentBytes) * 8 / 5 / 1e6)
   ```
   Com o PC ocioso, valores altos indicam algo consumindo banda. Para achar o processo, peça para abrir o Monitor de Recursos (`resmon`) na aba Rede.
3. **Velocidade real de download** (consome cerca de 25 MB; pergunte se a conexão é limitada, como dados móveis):
   ```powershell
   [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
   $t = Measure-Command { $d = (New-Object Net.WebClient).DownloadData('https://speed.cloudflare.com/__down?bytes=26214400') }
   "{0:N1} Mbps (download, 1 conexão, {1:N0} MB)" -f (($d.Length * 8 / 1e6) / $t.TotalSeconds), ($d.Length / 1MB)
   ```
   É um indicador aproximado: uma única conexão TCP subestima links rápidos ou de alta latência. Para comparar com o plano contratado, use também um teste de velocidade no navegador.
4. **Wi-Fi ou cabo?** Se a velocidade é boa no cabo e ruim no Wi-Fi, volte à Rota A.
5. **Rede local lenta mas internet ok** (arquivos no NAS, impressora): mede-se com `iperf3` entre dois pontos da rede, ferramenta externa que só deve ser instalada com a permissão do usuário.

## Rota D - Intermitência, perda de pacotes e jitter

Compare gateway e internet ao mesmo tempo para ver onde a perda nasce:

| Padrão | Leitura |
|---|---|
| Perda já no gateway | Local: Wi-Fi, cabo ou roteador |
| Gateway limpo, perda na internet | Roteador para o provedor, ou o trecho adiante |
| Perda só em um destino | Problema desse destino ou da rota até ele |
| Latência sobe junto com o uso da rede | Congestionamento ou bufferbloat (roteador sem gestão de fila) |

Para falhas que vêm e vão, registre um período e analise depois (peça ao usuário a duração; se for longa, rode em segundo plano com `Start-Job` para não estourar o tempo do terminal):

```powershell
$minutos = 10
$alvos   = @($gw, '1.1.1.1')          # $gw da foto rápida
$arq     = Join-Path $env:TEMP 'monitor-rede.csv'
$fim     = (Get-Date).AddMinutes($minutos)
$ping    = New-Object System.Net.NetworkInformation.Ping
'hora,alvo,ms' | Set-Content $arq
while ((Get-Date) -lt $fim) {
    foreach ($a in $alvos) {
        try { $r = $ping.Send($a, 1500); $ms = if ($r.Status -eq 'Success') { $r.RoundtripTime } else { 'perda' } } catch { $ms = 'perda' }
        ('{0},{1},{2}' -f (Get-Date -Format 'HH:mm:ss'), $a, $ms) | Add-Content $arq
    }
    Start-Sleep -Seconds 1
}
Import-Csv $arq | Group-Object alvo | ForEach-Object {
    [pscustomobject]@{ Alvo = $_.Name; Amostras = $_.Count; Perdas = @($_.Group | Where-Object { $_.ms -eq 'perda' }).Count }
}
```

Para localizar **onde** no caminho (use o IP, `-d` evita demora de DNS):

```powershell
tracert -d -h 15 -w 1000 8.8.8.8
pathping -n -q 20 -h 12 8.8.8.8     # leva alguns minutos; avise o usuário
```

**Como ler traceroute sem se enganar:** latência alta ou perda que aparece num salto intermediário mas **não continua** nos saltos seguintes e no destino é só o roteador daquele salto deprioritizando respostas ICMP; não é problema real. Só conta quando o problema **persiste até o destino**. Linhas com `*` no meio e destino alcançável também são normais.

Verifique ainda conflito de IP e quedas registradas pelo sistema (Rota H e `Get-WinEvent` no log System).

## Rota E - Site, servidor ou porta específica

1. **Nome ou IP?** Teste por IP e por nome. Falha só por nome: Rota B.
2. **Porta:**
   ```powershell
   Test-PortaTcp -Alvo 'servidor.exemplo.com' -Porta 443
   ```
   | Estado | Leitura |
   |---|---|
   | Aberta | Rede e serviço respondem; o problema é de aplicação, autenticação ou certificado |
   | Recusada | O host está no ar, mas o serviço está parado ou a porta é outra |
   | Timeout | Firewall (local, do servidor ou do caminho), ou sem rota |
   Portas comuns: 80/443 web, 53 DNS, 22 SSH, 3389 RDP, 445 SMB, 25/587 e-mail de saída, 3306 MySQL, 5432 PostgreSQL.
3. **Web:** `Invoke-WebRequest <url> -Method Head -UseBasicParsing -TimeoutSec 10` mostra o código HTTP (200 ok, 403 bloqueio, 407 proxy, 5xx servidor). Erro de certificado com data errada no PC (`Get-Date`) é causa clássica.
4. **Local ou remoto?** Teste do hotspot do celular ou de outro dispositivo. Funciona lá: problema na rede, firewall ou proxy do usuário. Falha em todo lugar: o destino.
5. **Caminho:** `tracert -d <alvo>` e a leitura da Rota D.
6. Site lento só às vezes? Compare IPv4 e IPv6 (`Resolve-DnsName <nome> -Type AAAA`); IPv6 mal roteado causa atraso antes do fallback para IPv4.

## Rota F - Rede local e compartilhamento (SMB)

1. O servidor/PC responde? `Test-PortaTcp -Alvo <host> -Porta 445`. Timeout é firewall ou rede; recusada é SMB desligado.
2. O nome resolve? `Resolve-DnsName <host>`. Se só o IP funciona, o problema é resolução de nomes: use o IP ou corrija o DNS.
3. **Perfil de rede:** `Get-NetConnectionProfile` com `NetworkCategory` = `Public` bloqueia descoberta e compartilhamento. Em rede de confiança, trocar para `Private` (com confirmação) libera: `Set-NetConnectionProfile -InterfaceAlias <nome> -NetworkCategory Private`.
4. **Credenciais:** `cmdkey /list` mostra credenciais salvas que podem estar velhas e causar "acesso negado". Remover uma é ação que altera, então confirme.
5. Mensagens como "caminho de rede não encontrado" (0x80070035) apontam para nome ou porta 445. Versões recentes do Windows bloqueiam acesso de convidado sem autenticação e exigem assinatura SMB em certos cenários; confirme na documentação da Microsoft antes de relaxar qualquer política, pois isso reduz a segurança.
6. Para descobrir dispositivos já vistos na rede do usuário, `arp -a` ou `Get-NetNeighbor` bastam; não varra a faixa.
7. Impressora de rede? A skill `diagnostico-impressora`, se disponível, cobre o resto.

## Rota G - VPN, proxy e firewall

```powershell
# Proxy do usuário e do sistema
Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' | Select-Object ProxyEnable, ProxyServer, AutoConfigURL
netsh winhttp show proxy

# Firewall
Get-NetFirewallProfile | Select-Object Name, Enabled, DefaultInboundAction, DefaultOutboundAction

# Rotas padrão (mais de uma costuma indicar VPN em túnel completo ou duas redes)
Get-NetRoute -AddressFamily IPv4 -DestinationPrefix '0.0.0.0/0' | Select-Object InterfaceAlias, NextHop, RouteMetric
Get-VpnConnection -ErrorAction SilentlyContinue | Select-Object Name, ServerAddress, ConnectionStatus, SplitTunneling
```

- **Proxy ligado** (`ProxyEnable` = 1 ou `AutoConfigURL` preenchido) que o usuário não conhece: causa clássica de "navegador falha, ping funciona". Mostre e pergunte se é da empresa antes de desligar.
- **VPN:** o problema some com a VPN desligada? Compare (peça autorização, pois derruba acessos que dependem dela). VPN em túnel completo manda tudo pelo servidor da empresa e pode deixar a internet lenta ou o DNS interno quebrado.
- **Firewall:** desligar o firewall para testar é arriscado; prefira testar uma regra de entrada específica para a porta em questão, ou peça para quem administra a rede verificar. Se o firewall é do servidor, a falha aparece como **Timeout** no `Test-PortaTcp`.
- **Portal cativo** (hotel, café, escola): a resposta do teste do Windows na foto rápida vem diferente. Abrir qualquer site `http` no navegador costuma levar à página de login da rede.
- Segurança de rede corporativa pode bloquear de propósito: em máquina gerenciada, respeite a política e leve a evidência ao TI em vez de contorná-la.

## Rota H - IP, DHCP e conflitos

```powershell
Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -ne '127.0.0.1' } |
    Select-Object InterfaceAlias, IPAddress, PrefixLength, PrefixOrigin, AddressState | Format-Table -AutoSize
```

- **169.254.x.x (APIPA):** o computador não conseguiu IP do DHCP. Verifique o cabo ou o Wi-Fi (Rota A), reinicie o roteador e tente renovar (ver Correções).
- **IP numa faixa inesperada** (ex.: 192.168.1.x quando a rede é 192.168.0.x) ou **servidor DHCP que não é o roteador**: dá para ver em `ipconfig /all` (campos de servidor DHCP e concessão). Um segundo roteador ligado por engano na rede, distribuindo IPs, é causa clássica de comportamento estranho.
- **Conflito de IP:** o Windows registra o evento 4199 do Tcpip:
  ```powershell
  try {
      Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'Tcpip'; Id = 4199; StartTime = (Get-Date).AddDays(-7) } -MaxEvents 5 -ErrorAction Stop |
          Select-Object TimeCreated, Message | Format-List
  } catch { 'Sem eventos de conflito de IP nos últimos 7 dias.' }
  ```
  Dois dispositivos com o mesmo IP fixo causam quedas aleatórias. A correção é um só deles usar DHCP ou outro IP; reserve IPs no roteador para dispositivos que precisam de endereço estável.

---

## Correções (sempre com confirmação)

Anote o valor anterior antes de alterar, para poder reverter. Em máquina de empresa, pergunte se há política que fixe a configuração.

| Ação | Comando (administrador) | Risco e observações | Reversão |
|---|---|---|---|
| Limpar cache DNS | `Clear-DnsClientCache` | Baixo. Resolve respostas velhas | Não precisa |
| Renovar IP | `ipconfig /renew` | Interrompe a conexão por instantes; derruba sessão remota | Automática |
| Reiniciar adaptador | `Restart-NetAdapter -Name 'Wi-Fi'` | Derruba a conexão; avise antes | Automática |
| Trocar DNS do adaptador | `Set-DnsClientServerAddress -InterfaceAlias 'Wi-Fi' -ServerAddresses 1.1.1.1,8.8.8.8` | Quebra nomes internos em rede de domínio; mostra o DNS atual antes | `Set-DnsClientServerAddress -InterfaceAlias 'Wi-Fi' -ResetServerAddresses` |
| Perfil de rede Público para Privado | `Set-NetConnectionProfile -InterfaceAlias 'Wi-Fi' -NetworkCategory Private` | Só em rede de confiança: abre descoberta e compartilhamento | Voltar para `Public` |
| Reset da pilha de rede (último recurso) | `netsh winsock reset` e `netsh int ip reset` | Exige reiniciar; pode afetar VPN e softwares de segurança que se acoplam à rede; perde configurações de IP personalizadas | Não há; anote antes (`ipconfig /all`) |

Antes de trocar DNS, registre o atual: `(Get-DnsClientServerAddress -InterfaceAlias 'Wi-Fi' -AddressFamily IPv4).ServerAddresses`. Depois de **qualquer** correção, repita a foto rápida (Passo 1) e compare com a anterior. Um comando sem erro não prova que resolveu.

## Passo 3 - Encerrar

Feche com um resumo curto no formato:

- **Camada onde falha:** (ex.: DNS do roteador)
- **Evidências:** os números que sustentam (perda, latência, estado das portas, resposta do DNS)
- **Causa provável**
- **O que alterei**, com o valor anterior para reverter
- **O que depende de outra pessoa** (provedor, TI, administrador do servidor)

Mascare IP público, MAC e SSID se o resumo for ser encaminhado.

## Escalonamento

Escale (provedor, TI, administrador do servidor, fabricante) quando duas rotas diferentes falharam, quando o problema só ocorre de fora da rede do usuário, ou quando a falha está no equipamento do provedor ou do servidor. Leve evidência concreta, que é o que faz o suporte agir:

- **Provedor:** horário e duração das falhas, perda e latência medidas até o gateway e até a internet (Rota D), resultado do `pathping`, e o fato de que o problema persiste com outro dispositivo e com cabo direto no modem (se testado).
- **Administrador do servidor:** alvo e porta testados, estado retornado (Recusada ou Timeout), horário, e o resultado do mesmo teste a partir de outra rede.
- Quando for o caso, sugira trocar o cabo, testar outro roteador ou modem emprestado, ou contratar uma visita técnica, em vez de insistir em configurações.

## Equivalentes em Linux e macOS

Se a máquina for Linux ou macOS (e for a do usuário), mantenha o mesmo método de camadas com estes comandos:

| Objetivo | Linux | macOS |
|---|---|---|
| IP, interface, gateway | `ip addr`, `ip route` | `ifconfig`, `netstat -rn`, `networksetup -getinfo Wi-Fi` |
| Ping com amostras | `ping -c 20 <alvo>` | `ping -c 20 <alvo>` |
| DNS (servidor específico) | `dig @1.1.1.1 <nome>` ou `resolvectl query <nome>` | `dig @1.1.1.1 <nome>` ou `scutil --dns` |
| Teste de porta | `nc -zv -w 3 <host> <porta>` | `nc -zv -G 3 <host> <porta>` |
| Traceroute | `traceroute -n <alvo>` ou `mtr -rwn <alvo>` | `traceroute -n <alvo>` |
| Conexões e portas locais | `ss -tulpn` | `lsof -i -P -n` |
| Wi-Fi | `nmcli dev wifi` | `/System/Library/PrivateFrameworks/Apple80211.framework/Resources/airport -I` (versões antigas) ou Informações do Sistema |
| Limpar cache DNS | `resolvectl flush-caches` | `sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder` |
