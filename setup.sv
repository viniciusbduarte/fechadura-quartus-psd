// ============================================================================
// MÓDULO SETUP - FECHADURA ELETRÔNICA
// ============================================================================
// Responsável por gerenciar os menus de configuração do sistema, alteração de
// tempos, status do bip e cadastro de senhas (Master + 4 Usuários).
// ============================================================================
import projeto_types::*; // Importa os tipos do pacote

module setup (
    input  logic         clk,              // Clock do sistema (frequência de 1 kHz)
    input  logic         rst,              // Reset síncrono global (Ativo em nível ALTO)
    input  logic         setup_on,         // Sinal de habilitação: bloco opera apenas em '1'
    
    // --- Interface com Módulo Teclado ---
    input  digitosPac_t    digitos_value,    // Estrutura packed com os dígitos contidos no barramento
    input  logic         digitos_valid,    // Pulso (1 ciclo) indicando nova atividade/evento no teclado
    
    // --- Interface com Displays de 7 Segmentos ---
    output logic         display_en,       // Ativa o controle do display no modo setup (display_s = 1)
    output bcdPac_t      bcd_pac,          // Estrutura com dados BCD formatados (BCD5 até BCD0)
    
    // --- Interface de Saída de Configuração ---
    output setupPac_t    data_setup_new,   // barramento contínuo com a estrutura de dados atualizada
    output logic         data_setup_ok     // Pulso/Sinalizador de commit (dados prontos para gravação)
);

    // ==========================================
    // DEFINIÇÕES DE ESTADO DA FSM (9 MENUS + IDLE/COMMIT)
    // ==========================================
    typedef enum logic [3:0] {
        ST_IDLE,              // Estado fora de operação ou aguardando ativação de 'setup_on'
        ST_QUAL_MENU_00,      // Menu "00": Aguarda entrada de dois dígitos para navegar até outro menu
        ST_MENU_BIP_01,       // Menu "01": Ativa (1) ou desativa (0) o alerta sonoro de porta aberta
        ST_MENU_T_BIP_02,     // Menu "02": Altera o tempo limite até disparar o bip (5s a 60s)
        ST_MENU_T_LOCK_03,    // Menu "03": Altera o tempo para o travamento automático (5s a 60s)
        ST_MENU_PASS_M_04,    // Menu "04": Cadastro/Atualização da Senha Master
        ST_MENU_PASS_1_05,    // Menu "05": Cadastro/Atualização da Senha do Usuário 1
        ST_MENU_PASS_2_06,    // Menu "06" : Cadastro/Atualização da Senha do Usuário 2
        ST_MENU_PASS_3_07,    // Menu "07": Cadastro/Atualização da Senha do Usuário 3
        ST_MENU_PASS_4_08,    // Menu "08": Cadastro/Atualização da Senha do Usuário 4
        ST_MENU_EXIT_09,      // Menu "09": Menu de confirmação de saída do setup
        ST_COMMIT             // Efetua a gravação final e avisa o sistema operacional (data_setup_ok = 1)
    } state_t;

    state_t state;            // Registrador que armazena o estado atual da FSM
    setupPac_t draft_config;  // Registrador temporário (rascunho) para guardar dados modificados localmente
    logic [3:0] current_menu; // Armazena o índice do menu atual (00 a 09) para amostragem no display
	 logic [7:0] val; 			// Armazena valor de tempo para o menu 02 e 03

    // ==========================================
    // DEFINIÇÕES DE VALORES ESPECIAIS DO TECLADO
    // ==========================================
    localparam logic [3:0] KEY_HASH    = 4'hB; // Tecla '#': Aborta operação imediata e invoca Menu 09
    localparam logic [3:0] EVT_TIMEOUT = 4'hE; // Evento de estouro de tempo (Deve ser totalmente ignorado aqui)
    localparam logic [3:0] VAL_EMPTY   = 4'hF; // Código que representa ausência de dígito pressionado (Vazio)

    // ==========================================
    // LÓGICA DE FORMATAÇÃO DO DISPLAY (HEX5-HEX0)
    // ==========================================
    // Conforme Item 13: HEX5 e HEX4 exibem o menu atual. HEX3 a HEX0 ficam desativados/apagados (0xF).
    assign bcd_pac.BCD5     = current_menu / 10; // Extrai a dezena do índice do menu ativo
    assign bcd_pac.BCD4     = current_menu % 10; // Extrai a unidade do índice do menu ativo
    assign bcd_pac.BCD3     = VAL_EMPTY;         // Display HEX3 apagado
    assign bcd_pac.BCD2     = VAL_EMPTY;         // Display HEX2 apagado
    assign bcd_pac.BCD1     = VAL_EMPTY;         // Display HEX1 apagado
    assign bcd_pac.BCD0     = VAL_EMPTY;         // Display HEX0 apagado
    assign display_en       = setup_on;          // Habilitação do display controlada pelo setup_on

    // ==========================================
    // MÁQUINA DE ESTADOS SEQUENCIAL (FSM)
    // ==========================================
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            // --- Condição de Reset do Sistema (Valores de Fábrica) ---
            state           <= ST_IDLE;
            data_setup_ok   <= 1'b0;
            current_menu    <= 4'd0;
            
            draft_config.bip_status      <= 1'b1; // Bip ativado por padrão
            draft_config.bip_time        <= 6'd5;  // Tempo padrão de 5 segundos
            draft_config.tranca_aut_time <= 6'd5;  // Tempo de tranca padrão de 5 segundos
            draft_config.senha_master    <= {16'hFFFF, 4'h1, 4'h2, 4'h3, 4'h4}; // Senha Master padrão: 1234
            draft_config.senha_1         <= {20{VAL_EMPTY}}; // Senha 1 limpa
            draft_config.senha_2         <= {20{VAL_EMPTY}}; // Senha 2 limpa
            draft_config.senha_3         <= {20{VAL_EMPTY}}; // Senha 3 limpa
            draft_config.senha_4         <= {20{VAL_EMPTY}}; // Senha 4 limpa
        end 
        else if (!setup_on) begin
            state         <= ST_IDLE;
            data_setup_ok <= 1'b0; 
        end 
        else begin
            case (state)
                
                // --- ESTADO IDLE: AGUARDANDO SINAL SETUP_ON ---
                ST_IDLE: begin
                    current_menu  <= 4'd0;
                    //data_setup_ok <= 1'b0;
                    state         <= ST_QUAL_MENU_00; // Avança diretamente para o menu inicializador
                end

                // --- MENU 00: SELEÇÃO DE MENUS OPERACIONAIS ---
                ST_QUAL_MENU_00: begin
                    current_menu <= 4'd0; // Atualiza display para mostrar "00"
                    
                    // Validação de segurança: ignora completamente o pulso se for provocado por timeout (0xE)
                    if (digitos_valid && (digitos_value.digits[0] != EVT_TIMEOUT)) begin
                        if (digitos_value.digits[0] == KEY_HASH) begin
                            state <= ST_MENU_EXIT_09; // Se pressionar '#' isolado, pula para a tela de saída
                        end
                        else begin
                            // Lê a composição dos dois últimos dígitos armazenados no barramento para selecionar o menu
                            case ({digitos_value.digits[1], digitos_value.digits[0]})
                                8'h01: state <= ST_MENU_BIP_01;
                                8'h02: state <= ST_MENU_T_BIP_02;
                                8'h03: state <= ST_MENU_T_LOCK_03;
                                8'h04: state <= ST_MENU_PASS_M_04;
                                8'h05: state <= ST_MENU_PASS_1_05;
                                8'h06: state <= ST_MENU_PASS_2_06;
                                8'h07: state <= ST_MENU_PASS_3_07;
                                8'h08: state <= ST_MENU_PASS_4_08;
                                8'h09: state <= ST_MENU_EXIT_09;
                                default: state <= ST_QUAL_MENU_00; // Combinações inexistentes são ignoradas
                            endcase
                        end
                    end
                end

                // --- MENU 01: ATIVAR/DESATIVAR ALERTA SONORO ---
                ST_MENU_BIP_01: begin
                    current_menu <= 4'd1; // Atualiza display para mostrar "01"
                    if (digitos_valid && (digitos_value.digits[0] != EVT_TIMEOUT)) begin
                        if (digitos_value.digits[0] == KEY_HASH) begin
                            state <= ST_MENU_EXIT_09; // Aborta e pula para o Menu 09
                        end 
                        else if (digitos_value.digits[0] == 4'h1) begin
                            draft_config.bip_status <= 1'b1; // Altera temporariamente: Ativa Bip
                            state                   <= ST_QUAL_MENU_00; // Confirmação implícita, retorna para o menu 00
                        end 
                        else if (digitos_value.digits[0] == 4'h0) begin
                            draft_config.bip_status <= 1'b0; // Altera temporariamente: Desativa Bip
                            state                   <= ST_QUAL_MENU_00; // Confirmação implícita, retorna para o menu 00
                        end
                        else begin
                            state <= ST_QUAL_MENU_00; // Caso confirme sem mudar o valor, apenas retorna ao menu 00
                        end
                    end
                end

                // --- MENU 02: CONFIGURAÇÃO DE TEMPO DO BIP (5s A 60s) ---
                ST_MENU_T_BIP_02: begin
                    current_menu <= 4'd2; // Atualiza display para mostrar "02"
                    if (digitos_valid && (digitos_value.digits[0] != EVT_TIMEOUT)) begin
                        if (digitos_value.digits[0] == KEY_HASH) begin
                            state <= ST_MENU_EXIT_09; // Aborta a operação e pula para o Menu 09
                        end
                        else begin
                            // Converte a dezena e unidade contidas nos últimos dígitos do pacote para formato inteiro
                            val = (digitos_value.digits[1] * 10) + digitos_value.digits[0];
                            // Saturação por hardware para blindar os limites físicos aceitáveis do contador
                            if (val < 8'd5)  val = 8'd5;
                            if (val > 8'd60) val = 8'd60;

                            draft_config.bip_time <= val[5:0]; // Salva o tempo tratado no rascunho
                            state                 <= ST_QUAL_MENU_00;  // Retorna para o menu principal
                        end
                    end
                end

                // --- MENU 03: CONFIGURAÇÃO DE TEMPO DE TRANCA AUTOMÁTICA (5s A 60s) ---
                ST_MENU_T_LOCK_03: begin
                    current_menu <= 4'd3; // Atualiza display para mostrar "03"
                    if (digitos_valid && (digitos_value.digits[0] != EVT_TIMEOUT)) begin
                        if (digitos_value.digits[0] == KEY_HASH) begin
                            state <= ST_MENU_EXIT_09; // Aborta e desvia para o Menu 09
                        end
                        else begin
                            // Realiza o cálculo de conversão BCD para Decimal baseado no barramento atual
                            val = (digitos_value.digits[1] * 10) + digitos_value.digits[0];
                            if (val < 8'd5)  val = 8'd5;
                            if (val > 8'd60) val = 8'd60;

                            draft_config.tranca_aut_time <= val[5:0]; // Atualiza o parâmetro no rascunho
                            state                        <= ST_QUAL_MENU_00;  // Retorna para o menu principal
                        end
                    end
                end

                // --- MENU 04: CONFIGURAÇÃO DE SENHA MASTER ---
                ST_MENU_PASS_M_04: begin
                    current_menu <= 4'd4; // Atualiza display para mostrar "04"
                    if (digitos_valid && (digitos_value.digits[0] != EVT_TIMEOUT)) begin
                        if (digitos_value.digits[0] == KEY_HASH) begin
                            state <= ST_MENU_EXIT_09; // Aborta de imediato indo para o Menu 09
                        end
                        else begin
                            // [Caso 1 e 3]: Se o dígito de índice 3 não for vazio (0xF), a senha possui pelo menos 4 dígitos legítimos
                            // [Caso 2]: Se digits[3] == 0xF, a senha possui menos de 4 dígitos (Muito curta). Descarte total.
                            if (digitos_value.digits[3] != VAL_EMPTY) begin
                                draft_config.senha_master <= digitos_value; // Salva o pacote completo (Mantém até as últimas 12 inserções)
                                state <= ST_QUAL_MENU_00; // Retorna para o menu principal limpando a operação
                            end
                        end
                    end
                end

                // --- MENU 05: CONFIGURAÇÃO DE SENHA USUÁRIO 1 ---
                ST_MENU_PASS_1_05: begin
                    current_menu <= 4'd5; // Atualiza display para mostrar "05"
                    if (digitos_valid && (digitos_value.digits[0] != EVT_TIMEOUT)) begin
                        if (digitos_value.digits[0] == KEY_HASH) begin
                            state <= ST_MENU_EXIT_09;
                        end
                        else begin
                            if (digitos_value.digits[3] != VAL_EMPTY) begin
                                draft_config.senha_1 <= digitos_value; // Efetua gravação após passar no crivo de validação de tamanho mínimo
                                state <= ST_QUAL_MENU_00;
                            end
                        end
                    end
                end

                // --- MENU 06: CONFIGURAÇÃO DE SENHA USUÁRIO 2 ---
                ST_MENU_PASS_2_06: begin
                    current_menu <= 4'd6; // Atualiza display para mostrar "06"
                    if (digitos_valid && (digitos_value.digits[0] != EVT_TIMEOUT)) begin
                        if (digitos_value.digits[0] == KEY_HASH) begin
                            state <= ST_MENU_EXIT_09;
                        end
                        else begin
                            if (digitos_value.digits[3] != VAL_EMPTY) begin
                                draft_config.senha_2 <= digitos_value; // Efetua gravação após passar no crivo de validação de tamanho mínimo
                                state <= ST_QUAL_MENU_00;
                            end
                        end
                    end
                end

                // --- MENU 07: CONFIGURAÇÃO DE SENHA USUÁRIO 3 ---
                ST_MENU_PASS_3_07: begin
                    current_menu <= 4'd7; // Atualiza display para mostrar "07"
                    if (digitos_valid && (digitos_value.digits[0] != EVT_TIMEOUT)) begin
                        if (digitos_value.digits[0] == KEY_HASH) begin
                            state <= ST_MENU_EXIT_09;
                        end
                        else begin
                            if (digitos_value.digits[3] != VAL_EMPTY) begin
                                draft_config.senha_3 <= digitos_value; // Efetua gravação após passar no crivo de validação de tamanho mínimo
                                state <= ST_QUAL_MENU_00;
                            end
                        end
                    end
                end

                // --- MENU 08: CONFIGURAÇÃO DE SENHA USUÁRIO 4 ---
                ST_MENU_PASS_4_08: begin
                    current_menu <= 4'd8; // Atualiza display para mostrar "08"
                    if (digitos_valid && (digitos_value.digits[0] != EVT_TIMEOUT)) begin
                        if (digitos_value.digits[0] == KEY_HASH) begin
                            state <= ST_MENU_EXIT_09;
                        end
                        else begin
                            if (digitos_value.digits[3] != VAL_EMPTY) begin
                                draft_config.senha_4 <= digitos_value; // Gravação aceita com sucesso
                                state <= ST_QUAL_MENU_00;
                            end
                        end
                    end
                end

                // --- MENU 09: MENU DE SAÍDA (TELA DE SELEÇÃO FINAL) ---
                ST_MENU_EXIT_09: begin
                    current_menu <= 4'd9; // Atualiza display para mostrar "09"
                    if (digitos_valid && (digitos_value.digits[0] != EVT_TIMEOUT)) begin
                        if (digitos_value.digits[0] == KEY_HASH) begin
                            state <= ST_QUAL_MENU_00; // Tecla '#' cancela o desejo de sair e retorna ao menu 00
                        end 
                        else begin
                            state <= ST_COMMIT;       // Qualquer outra tecla ou pulso válido confirma a gravação final (Ex: '*')
                        end
                    end
                end

                // --- ETAPA DE COMMIT: PULSAR SINAL DE CONFIGURAÇÃO PRONTA ---
                ST_COMMIT: begin
                    data_setup_ok <= 1'b1;   // Pulsa o sinalizador em nível alto indicando ao sistema que os dados são íntegros
                    state         <= ST_IDLE; // Desvia o fluxo de volta para o IDLE fechando o ciclo de edição do Setup
                end

            endcase
        end
    end

    // Saída contínua: disponibiliza em tempo real a estrutura rascunho no barramento 'data_setup_new'
    assign data_setup_new = draft_config; 

endmodule


