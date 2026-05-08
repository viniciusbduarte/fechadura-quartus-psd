<h1 align="center">
  🔒 Fechadura Eletrônica Inteligente em SystemVerilog (FPGA)
</h1>

<p align="center">
  <img src="https://img.shields.io/badge/SystemVerilog-000000?style=for-the-badge&logo=SystemVerilog&logoColor=white" />
  <img src="https://img.shields.io/badge/Intel_Quartus-1065AB?style=for-the-badge&logo=intel&logoColor=white" />
  <img src="https://img.shields.io/badge/Hardware-Design-red?style=for-the-badge" />
</p>

<p align="center">
  <b>Um projeto completo de sistema digital para controle de acesso usando Máquinas de Estados Finitas (FSM) e Arquitetura Modular.</b><br>
  <i>Desenvolvido para placa FPGA operando com clock de 1KHz.</i>
</p>

---

## 🔍 Visão Geral
Este projeto consiste no desenvolvimento e implementação em SystemVerilog de uma fechadura eletrônica dotada de alta segurança. O sistema não apenas valida senhas, mas conta com medidas anti-espionagem (adição de dígitos aleatórios antes ou depois da senha), funções de bloqueio temporário, alarmes (BIP) para porta aberta, além de um **Modo Setup** exclusivo para configuração de parâmetros de usuário e do sistema.

A lógica central opera como uma **Máquina de Estados Finita (FSM)** robusta, assegurando sincronismo rígido, debouncing de botões, decodificação matricial de teclado e multiplexação de displays de 7 segmentos.

---

## 🏗 Arquitetura do Sistema
O sistema é gerido pela `FechaduraTop`, a "casca" principal (Top-Level) que mapeia as entradas e saídas físicas para os submódulos lógicos.

<p align="center">
  <img src="./Diagrama_FechaduraEletronica-2026.1.jpg" alt="Diagrama de Blocos da Fechadura" width="800">
</p>

*O diagrama mostra a comunicação bidirecional sincronizada entre os módulos **Operacional** e **Setup**, a decodificação de teclado através de structs empacotadas BCD e o tratamento visual dos LEDs.*

---

## ✨ Funcionalidades Principais

### 🛡️ Modo Operacional (Controle de Acesso)
* **Múltiplos Usuários:** Suporta o armazenamento de 4 senhas de usuário independentes.
* **Tamanho Flexível:** Senhas de **4 a 12 dígitos** configuráveis.
* **Camuflagem de Senha:** O sistema permite a entrada de até 21 dígitos numéricos, ignorando números aleatórios ("lixo") postos antes e/ou depois da senha real antes de ser pressionado o `*`.
* **Bloqueio de Segurança:** Se o usuário errar a senha por 5 tentativas seguidas, a fechadura entrará em modo de bloqueio compulsório de 30 segundos, ignorando completamente o teclado matricial.
* **Controle de Tempo (Timeout):** Há um timeout de 5s entre toques de teclas. Se esse tempo estourar sem finalizar a digitação, o progresso atual é descartado e o bip é acionado.
* **Trancamento Inteligente:** Conta com travamento automático se a porta não for aberta num tempo limite (default 5s) e um *Bip de Alerta* caso a porta fique esquecida aberta.

### ⚙️ Modo Setup (Configuração)
Acessado somente com a porta destravada, a tecla interna "Config" aciona uma FSM sequencial dedicada a personalizações:
1. **Ativar/Desativar BIP** (Opção 01)
2. **Tempo do BIP** (Opção 02: 5s a 60s)
3. **Tempo de Fechamento Automático** (Opção 03: 5s a 60s)
4. **Troca de Senha MASTER** (Opção 04)
5. **Trocas de Senhas Mestre e Padrão** (Opções 05 a 08)
   

---

## 🔌 Hardware e Interfaces

**Entradas Físicas:**
* Teclado Matricial 4x4 (Linhas/Colunas para input de senhas `0-9`, `*` e `#`).
* Chave de Contato (Detecta estado real da porta: aberta/fechada).
* Botão Bloqueio (Função "Não Perturbe" - trava o teclado externo por 3s contínuos pressionado).
* Botão Interno (Abertura local).
* Botão Configuração (Switch de modo).

**Saídas Físicas:**
* 6 Displays de 7-Segmentos (`HEX0` ao `HEX5`) para status, modo atual e timeout.
* 1 LED vermelho/verde para indicar fisicamente a Tranca Eletrônica atuando.

---

## 📂 Estrutura do Código e Arquivos do Projeto

O projeto é modularizado em arquivos SystemVerilog (`.sv`) e inclui os arquivos de configuração do Intel Quartus:

| Arquivo/Pasta | Descrição |
| :--- | :--- |
| `DE1_SOC_golden_top.sv` | Módulo *top-level* (casca) principal, adaptado para mapeamento direto com os pinos da placa DE1-SoC. Responsável por rotear os sinais de IO. |
| `projeto_types.sv` | Arquivo contendo as definições de dados customizadas (`typedef struct packed`), como `senhaPac_t`, `setupPac_t` e `bcdPac_t`, compartilhados entre os módulos. |
| `setup.sv` | Máquina de Estados do Modo de Configuração, gerencia os parâmetros de usuário, senhas, tempos e atualiza o sistema. |
| `decodificador_teclado.sv` | Controla e decodifica o teclado matricial 4x4, empacotando as teclas válidas num array de dígitos. |
| `debounce.sv` | Filtro digital para atenuar ruídos mecânicos (*bouncing*) dos push-buttons físicos. |
| `divfreq.sv` | Divisor de frequência de clock para gerar a base de tempo estrita de 1KHz para o sistema. |
| `segment7.sv` | Decodificador binário-BCD utilizado para o acionamento dos displays de 7 segmentos (`HEX0` ao `HEX5`). |
| `fechadura-eletronica.qpf` | Arquivo principal de projeto do Intel Quartus Prime (Quartus Project File). |
| `fechadura-eletronica.qsf` | Arquivo de configurações do Quartus (Quartus Settings File), incluindo pin planner e definições de compilação. |
---

## 📦 Protocolos e Customizações (Structs e Packages)
O projeto define Tipos Pre-Definidos fortemente tipados para comunicação Inter-módulo (IPC em hardware):

```systemverilog
// Empacotamento para senhas de até 20 dígitos BCD
typedef struct packed { 
    logic [19:0] [3:0] digits; 
} senhaPac_t;

// Empacotamento estruturado de todo o Setup da Placa
typedef struct packed {  
    logic        bip_status;  
    logic [5:0]  bip_time;  
    logic [5:0]  tranca_aut_time;  
    senhaPac_t   senha_master;  
    senhaPac_t   senha_1;  
    // ...
} setupPac_t;
```

---

<p align="center">
  <i>Desenvolvido com ☕ e SystemVerilog por <b>Isabelle Lavínia e Vinicius Duarte</b>.</i>
</p>
