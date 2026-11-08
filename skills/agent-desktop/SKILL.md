---
name: agent-desktop
description: Opera aplicativos desktop no Windows através da árvore nativa de acessibilidade (UI Automation) usando o agent-desktop. Use quando o agente precisar ver ou interagir com janelas e botões de interface gráfica (clicar em botões, preencher formulários, inspecionar telas, trocar opções e fechar pop-ups).
---

# Automação de Interface Gráfica com agent-desktop

O `agent-desktop` permite interagir com aplicativos gráficos no Windows sem mover fisicamente o cursor do mouse e sem necessidade de visão computacional. Ele lê a árvore nativa de acessibilidade e gera identificadores chamados `@ref`.

## 1. Regra Fundamental no PowerShell (Windows)
Sempre coloque aspas nos identificadores `@ref` (ex: `'@s8f3k2p9:e1'`), pois no PowerShell o `@` solto é interpretado como operador de *splatting*.

---

## 2. O Ciclo de Ação: Observar -> Agir -> Verificar

### Passo 1: Inspecionar uma janela aberta
Para mapear a interface e descobrir os elementos interativos:
```powershell
agent-desktop snapshot --app "NomeDoAplicativo" -i --compact
```
*Exemplo:* `agent-desktop snapshot --app "Configurações" -i --compact`

### Passo 2: Clicar em um botão ou elemento
Use a referência obtida no snapshot anterior:
```powershell
agent-desktop click '@refId'
```

### Passo 3: Digitar texto em um campo
```powershell
agent-desktop type '@refId' "texto a digitar"
```

### Passo 4: Aguardar um elemento aparecer
```powershell
agent-desktop wait --element '@refId' --predicate actionable --timeout 5000
```

---

## 3. Comandos Úteis para Suporte e Diagnóstico

* **Listar todas as janelas abertas no Windows:**
  ```powershell
  agent-desktop list-windows
  ```
* **Trazer uma janela para a frente:**
  ```powershell
  agent-desktop focus-window --app "NomeDoApp"
  ```
* **Fechar um aplicativo:**
  ```powershell
  agent-desktop close-app --app "NomeDoApp"
  ```
* **Pressionar atalhos de teclado (ex: Enter, Esc, Ctrl+S):**
  ```powershell
  agent-desktop press enter
  agent-desktop press ctrl+s
  ```

---

## 4. Dica de Privilégios no Windows
Se o aplicativo que você deseja automatizar estiver rodando como Administrador (ou for uma janela protegida do sistema), certifique-se de que o `OpencodePortable.exe` foi iniciado como Administrador.
