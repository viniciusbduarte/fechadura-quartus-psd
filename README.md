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
Este projeto implementa, em SystemVerilog, uma fechadura eletrônica segura para FPGA com fluxo completo de entrada, validação e resposta do sistema. Além de validar senhas, o circuito adiciona camadas de proteção contra observação (entrada de dígitos aleatórios antes/depois da senha), aplica bloqueio temporário após tentativas inválidas e monitora a porta com alertas sonoros (BIP). Um **Modo Setup** dedicado permite ajustar parâmetros de usuário e do sistema sem reprogramação.

Toda a lógica é organizada em uma **Máquina de Estados Finita (FSM)** central e módulos auxiliares, garantindo sincronismo com clock de 1 kHz, tratamento de bounce em botões, leitura/decodificação de teclado matricial e multiplexação de 7 segmentos para feedback imediato ao usuário.

---

## 🏗 Arquitetura do Sistema
O sistema é gerido pela `DEC1_SOC_golden_top.sv`, a "casca" principal (Top-Level) que mapeia as entradas e saídas físicas para os submódulos lógicos.

<p align="center">
  <img src="/especificacoes/Diagrama_FechaduraEletronica-2026.1.png" alt="Diagrama de Blocos da Fechadura" width="800">
</p>

*O diagrama mostra a comunicação bidirecional sincronizada entre os módulos **Operacional** e **Setup**, a decodificação de teclado através de structs empacotadas BCD e o tratamento visual dos LEDs.*

---

## ✨ Funcionalidades Principais

### 🛡️ Modo Operacional (Controle de Acesso)
* **Múltiplos Usuários:** Suporta o armazenamento de 4 senhas de usuário independentes.
* **Tamanho Flexível:** Senhas de **4 a 12 dígitos** configuráveis.
* **Camuflagem de Senha:** O sistema permite a entrada de até 20 dígitos numéricos, ignorando números aleatórios ("lixo") postos antes e/ou depois da senha real antes de ser pressionado o `*`.
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
* 6 Displays de 7-Segmentos (`HEX0` ao `HEX5`) para senha, modo atual e status.
* 1 LED para indicar fisicamente a Tranca Eletrônica atuando.

---

## 📂 Estrutura do Código e Arquivos do Projeto

O projeto é modularizado em arquivos SystemVerilog (`.sv`) e inclui os arquivos de configuração do Intel Quartus:

| Arquivo/Pasta | Descrição |
| :--- | :--- |
| `DE1_SOC_golden_top.sv` | Módulo *top-level* (casca) principal, adaptado para mapeamento direto com os pinos da placa DE1-SoC. Responsável por rotear os sinais de IO. |
| `projeto_types.sv` | Arquivo contendo as definições de dados customizadas (`typedef struct packed`), como `digitosPac_t`, `senhaPac_t`, `setupPac_t` e `bcdPac_t`, compartilhados entre os módulos. |
| `setup.sv` | Máquina de Estados do Modo de Configuração, gerencia os parâmetros de usuário, senhas, tempos e atualiza o sistema. |
| `decodificador_teclado.sv` | Controla e decodifica o teclado matricial 4x4, empacotando as teclas válidas num array de dígitos. |
| `debounce.sv` | Filtro digital para atenuar ruídos mecânicos (*bouncing*) dos push-buttons físicos. |
| `divfreq.sv` | Divisor de frequência de clock para gerar a base de tempo estrita de 1KHz para o sistema. |
| `segment7.sv` | Decodificador binário-BCD utilizado para o acionamento dos displays de 7 segmentos (`HEX0` ao `HEX5`). |
| `fechadura-eletronica.qpf` | Arquivo principal de projeto do Intel Quartus Prime (Quartus Project File). |
| `fechadura-eletronica.qsf` | Arquivo de configurações do Quartus (Quartus Settings File), incluindo pin planner e definições de compilação. |
---

## 📦 Protocolos e Customizações (Structs e Packages)
O projeto define Tipos Pre-Definidos para comunicação entre os módulos do sistema:

```systemverilog
package projeto_types;
    typedef struct packed {
        logic [3:0] BCD5;
        logic [3:0] BCD4;
        logic [3:0] BCD3;
        logic [3:0] BCD2;
        logic [3:0] BCD1;
        logic [3:0] BCD0;
    } bcdPac_t;

    typedef struct packed {
        logic [11:0][3:0] digits;
    } senhaPac_t;
	 
	typedef struct packed {
        logic [19:0][3:0] digits;
    } digitosPac_t;

  
    typedef struct packed {
        logic        bip_status;
        logic [5:0]  bip_time;
        logic [5:0]  tranca_aut_time;
        senhaPac_t   senha_master;
        senhaPac_t   senha_1;
        senhaPac_t   senha_2;
        senhaPac_t   senha_3;
        senhaPac_t   senha_4;
    } setupPac_t;
endpackage
```

  **Legenda dos tipos:**
  * **`projeto_types`**: package que centraliza os tipos compartilhados pelos modulos.
  * **`bcdPac_t`**: pacote de 6 digitos BCD para exibicao nos 7 segmentos.
  * **`senhaPac_t`**: senha com ate 12 digitos BCD.
  * **`digitosPac_t`**: buffer de entrada com ate 20 digitos BCD.
  * **`setupPac_t`**: configuracoes do sistema (BIP, tempos e senhas dos usuarios).

## 🧩 Notas de Implementação (Displays no Modo Setup)

Durante o modo setup, o sistema implementa um comportamento especial de multiplex para os displays de 7 segmentos, garantindo clareza visual entre entrada de dados (modo operacional) e configuração de parâmetros (modo setup).

### Comportamento dos Displays por Modo

**Modo Operacional (SW[0] = 0):**
* Os 6 displays (HEX0–HEX5) exibem os dígitos que o usuário está digitando via teclado matricial.
* Estrutura: HEX5–HEX0 mostram `DIGITOS_VALUE.digits[5..0]` em tempo real.

**Modo Setup (SW[0] = 1):**
* Os 4 primeiros displays (**HEX0–HEX3**) são apagados completamente.
* Os 2 últimos displays (**HEX4–HEX5**) exibem o número do menu de configuração ativo (00 até 09).

### Implementação Técnica

#### 1. No arquivo [setup.sv](setup.sv)
O módulo setup constrói um pacote BCD com os dados do menu a exibir:
```systemverilog
// Formato dos displays em modo setup:
// HEX5 = dezena do menu (0)
// HEX4 = unidade do menu (0–9)
// HEX3..HEX0 = VAL_EMPTY (4'hF) [não utilizados aqui]
assign bcd_pac.BCD5 = current_menu / 10;  // Dezena (p.ex., menu 05 → BCD5=0)
assign bcd_pac.BCD4 = current_menu % 10;  // Unidade (p.ex., menu 05 → BCD4=5)
assign bcd_pac.BCD3 = VAL_EMPTY;          // Ignorado na multiplexacao
assign bcd_pac.BCD2 = VAL_EMPTY;          // Ignorado na multiplexacao
assign bcd_pac.BCD1 = VAL_EMPTY;          // Ignorado na multiplexacao
assign bcd_pac.BCD0 = VAL_EMPTY;          // Ignorado na multiplexacao
```

#### 2. No arquivo [DE1_SOC_golden_top.sv](DE1_SOC_golden_top.sv)
O multiplexador principal detecta `SW_0` e roteia os dados conforme o modo:
```systemverilog
// Multiplex de 7 segmentos: Operacional vs Setup
always_comb begin
    if (SW_0) begin  // Modo Setup Ativo
        // Força HEX0–HEX3 para "apagado" (código 12)
        bcd_mux0 = 4'd12;
        bcd_mux1 = 4'd12;
        bcd_mux2 = 4'd12;
        bcd_mux3 = 4'd12;
        
        // HEX4–HEX5 exibem o número do menu
        bcd_mux4 = {1'b0, BUS_DISPLAY.BCD4};  // Unidade
        bcd_mux5 = {1'b0, BUS_DISPLAY.BCD5};  // Dezena
    end
    else begin  // Modo Operacional
        // Todos os 6 displays mostram dígitos do teclado
        bcd_mux0 = {1'b0, DIGITOS_VALUE.digits[0]};
        bcd_mux1 = {1'b0, DIGITOS_VALUE.digits[1]};
        bcd_mux2 = {1'b0, DIGITOS_VALUE.digits[2]};
        bcd_mux3 = {1'b0, DIGITOS_VALUE.digits[3]};
        bcd_mux4 = {1'b0, DIGITOS_VALUE.digits[4]};
        bcd_mux5 = {1'b0, DIGITOS_VALUE.digits[5]};
    end
end
```

#### 3. No arquivo [segment7.sv](segment7.sv)
O decodificador BCD-7 segmentos mapeia o código 12 para "apagado":
```systemverilog
// Tabela de decodificacao: BCD → 7 Segmentos
case (bcd)
    0  : seg = 7'b1000000;  // "0"
    1  : seg = 7'b1111001;  // "1"
    ...
    12 : seg = 7'b1111111;  // APAGADO (todos os bits em 1)
    13 : seg = 7'b0100001;  // "D"
    14 : seg = 7'b0000110;  // "E"
    15 : seg = 7'b0001110;  // "F"
endcase
```

### Resultado Visual
* **Modo Operacional:** `_ _ _ _ XX` (onde XX = dígitos 5–4 do buffer)
* **Modo Setup (p. ex., menu 03):** `        03` (apagado apagado apagado apagado 0 3)

---

<p align="center">
  <i>Desenvolvido com ☕ e SystemVerilog por <b>Isabelle Lavínia e Vinicius Duarte</b>.</i>
</p>
