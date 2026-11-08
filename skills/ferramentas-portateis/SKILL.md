---
name: ferramentas-portateis
description: Kit de ferramentas CLI portáteis pré-instaladas em .\bin\ (já no PATH da sessão) - ripgrep (rg), fd, jq, sqlite3 e utilitários Microsoft Sysinternals assinados digitalmente (handle, pslist, autorunsc). Use para buscar textos e logs rapidamente, localizar arquivos, filtrar JSON, inspecionar bancos SQLite locais e descobrir processos travando arquivos/pastas ou entradas de inicialização ocultas no Windows.
---

# Kit de Ferramentas Portáteis (`.\bin\`)

O **AgentStick** inclui um conjunto de binários portáteis em `.\bin\`, adicionado automaticamente ao `PATH` de todos os agentes (**OpenCode**, **Claude Code**, **GitHub Copilot CLI** e **Antigravity CLI**).

## 1. Busca Rápida de Arquivos e Logs (`rg` e `fd`)

Prefira `rg` (`ripgrep`) e `fd` em vez de `Get-ChildItem -Recurse` ou `Select-String` em pastas grandes — eles são ordens de magnitude mais rápidos:

```powershell
# Buscar erros ou padrões em arquivos de log/configuração (case-insensitive)
rg -i "error|exception|fatal|fail" C:\Windows\Logs\CBS\

# Localizar arquivos por nome ou extensão rapidamente
fd -e log -e json "config" C:\ProgramData\
```

## 2. Processamento e Triagem de JSON (`jq`)

Use `jq` para filtrar saídas JSON de APIs, configurações locais ou exportações do PowerShell:

```powershell
# Inspecionar chaves de um arquivo JSON formatado
jq "." config.json

# Filtrar campos específicos de uma lista JSON
Get-Process | Select-Object Name, Id, WS | ConvertTo-Json | jq ".[] | select(.WS > 500000000)"
```

## 3. Inspeção de Bancos de Dados Locais (`sqlite3`)

Use `sqlite3` em modo somente leitura para diagnosticar bancos de dados locais de aplicativos, históricos ou caches sem corromper locks ativos:

```powershell
# Listar tabelas de um banco SQLite
sqlite3 C:\caminho\banco.db ".tables"

# Executar consulta rápida em formato de tabela com cabeçalho
sqlite3 -header -column C:\caminho\banco.db "SELECT * FROM logs ORDER BY id DESC LIMIT 20;"

# Verificar integridade de um banco SQLite suspeito de corrupção
sqlite3 C:\caminho\banco.db "PRAGMA integrity_check;"
```

## 4. Microsoft Sysinternals Portáteis (`handle`, `pslist`, `autorunsc`)

Binários oficiais assinados digitalmente pela **Microsoft Corporation** (100% compatíveis com Windows 11 Smart App Control / Device Guard). Os atalhos `handle`, `pslist` e `autorunsc` em `.\bin\` já passam `-accepteula -nobanner` automaticamente para nunca travar esperando confirmação de licença:

### Descobrir qual processo está travando um arquivo ou pasta (`handle`)
 *(Requer terminal como Administrador)*
```powershell
# Ver qual processo está segurando um arquivo ou diretório que não deixa excluir/desmontar
handle "C:\caminho\do\arquivo-ou-pasta"
```

### Listar árvore e detalhes de processos e threads (`pslist`)
```powershell
# Visão de árvore de processos (quem iniciou quem)
pslist -t

# Detalhes de CPU e memória de um processo específico
pslist chrome
```

### Auditar tudo o que inicia com o Windows (`autorunsc`)
```powershell
# Exportar CSV com itens de logon, serviços de terceiros e tarefas agendadas (ocultando entradas padrão da Microsoft com -m)
autorunsc -a l -m -c
```

## Boas Práticas
- **Leitura é livre:** `rg`, `fd`, `jq`, `sqlite3` (consultas `SELECT` / `PRAGMA integrity_check`), `pslist`, `handle` (sem `-c`) e `autorunsc` apenas leem informações e podem ser executados sem confirmação.
- **Alteração exige confirmação:** fechar handles à força (`handle -c ...`), matar processos ou executar `UPDATE`/`DELETE` em bancos SQLite exige confirmação explícita do usuário.
