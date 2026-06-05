// ============================================================================
// MÓDULO OPERACIONAL - FECHADURA ELETRÔNICA
// ============================================================================
import projeto_types::*;

module operacional(
    input  logic        clk,
    input  logic        rst,
    input  logic        sensor_contato,
    input  logic        botao_interno,
    input  logic        botao_bloqueio,
    input  logic        botao_config,
    input  setupPac_t   data_setup_new,
    input  logic        data_setup_ok,
    input  digitosPac_t digitos_value,
    input  logic        digitos_valid,
    output bcdPac_t     bcd_pac,
    output logic        teclado_en,
    output logic        display_en,
    output logic        setup_on,
    output logic        tranca,
    output logic        bip
);

    // ==========================================
    // DEFINIÇÕES DE ESTADO DA FSM
    // ==========================================
    typedef enum logic [3:0] {
        ST_FECHADA_TRANCADA,
        ST_FECHADA_DESTRANCADA,
        ST_ABERTA_DESTRANCADA,
        ST_ACESSO_NEGADO,
        ST_BLOQUEADO,
        ST_AUTENTICA_CONFIG,
        ST_MODO_CONFIG
    } state_t;

    // ==========================================
    // CONSTANTES
    // ==========================================
    localparam logic [3:0] KEY_HASH    = 4'hB; // '#' cancelar
    localparam logic [3:0] EVT_TIMEOUT = 4'hE; // evento timeout do teclado
    localparam logic [3:0] VAL_EMPTY   = 4'hF; // ausência de dígito
    localparam logic [3:0] SEG_DASH    = 4'hA; // símbolo '-' no display 7-seg

    localparam int T_1S    = 1000;
    localparam int T_5S    = 5000;
    localparam int T_10S   = 10000;

    // ==========================================
    // REGISTRADORES INTERNOS
    // ==========================================
    state_t    state;
    state_t    state_return;  // estado a restaurar após rst
    setupPac_t config_atual;  // Registrador de configuração

    // Contador genérico de temporização (ms, base clock 1kHz)
    logic [16:0] timer;

    // Contador de duração do rst (ms, base clock 1kHz) — 14 bits cobre até ~16s
    logic [13:0] rst_timer;
    logic        rst_prev;

    // Registradores para detecção de borda de subida dos botões
    logic botao_interno_prev;
    logic botao_config_prev;
    logic botao_bloqueio_prev;

    wire botao_interno_rise  = botao_interno  & ~botao_interno_prev;
    wire botao_config_rise   = botao_config   & ~botao_config_prev;
    wire botao_bloqueio_rise = botao_bloqueio & ~botao_bloqueio_prev;


    bit sistema_inicializado; // Tipo 'bit' nasce em 0 automaticamente!
                          
    // Detecta descida do rst (negedge rst) no domínio do clk
    wire rst_fall = rst_prev & ~rst;

    // ==========================================
    // FUNÇÃO: VALIDAÇÃO POR JANELA DESLIZANTE
    // ==========================================
    function automatic logic senha_valida(
        input digitosPac_t entrada,
        input senhaPac_t   alvo
    );
        logic match;

        senha_valida = 1'b0;

        // Senha inválida (< 4 dígitos)
        if (alvo.digits[3] == VAL_EMPTY)
            return 1'b0;

        // Procura a senha em qualquer posição do buffer de 20 dígitos
        for (int i = 0; i <= 19; i++) begin

            match = 1'b1;

            for (int j = 0; j < 12; j++) begin

                // Só compara posições válidas da senha
                if (alvo.digits[j] != VAL_EMPTY) begin

                    // Evita acesso fora do vetor
                    if ((i + j) > 19)
                        match = 1'b0;

                    else if (entrada.digits[i + j] != alvo.digits[j])
                        match = 1'b0;
                end
            end

            if (match)
                return 1'b1;
        end

        return 1'b0;
    endfunction


    // ==========================================
    // WRAPPER PARA TODAS AS SENHAS
    // ==========================================
    function automatic logic qualquer_senha_valida(
        input digitosPac_t entrada,
        input setupPac_t   cfg
    );
        return senha_valida(entrada, cfg.senha_master) |
            senha_valida(entrada, cfg.senha_1)      |
            senha_valida(entrada, cfg.senha_2)      |
            senha_valida(entrada, cfg.senha_3)      |
            senha_valida(entrada, cfg.senha_4);
    endfunction

// ============================================================================
    // FSM PRINCIPAL + RESET SELETIVO CORRIGIDO (SÍNCRONO)
    // ============================================================================
    always_ff @(posedge clk) begin
        rst_prev <= rst; // Guarda o estado anterior do reset para detectar as bordas

        // ------------------------------------------------------------------------
        // 1. BOTÃO DE RESET PRESSIONADO: Conta o tempo e congela o histórico
        // ------------------------------------------------------------------------
        if (rst) begin
            rst_timer <= rst_timer + 1'b1;
            
            // Na exata batida de clock em que o botão foi apertado (borda de subida):
            if (rst_prev == 1'b0 && sistema_inicializado) begin
                state_return <= state; // Salva o estado atual real antes de resetar
            end
        end
        
        // ------------------------------------------------------------------------
        // 2. BOTÃO DE RESET FOI SOLTO (Borda de descida): Avalia a duração
        // ------------------------------------------------------------------------
        else if (rst_fall) begin
            rst_timer <= '0; // Limpa o contador para o próximo uso
            timer <= '0;

            // RESET TOTAL (Mínimo 10 segundos pressionado)
            if (rst_timer >= T_10S) begin
                config_atual.bip_status          <= 1'b1;
                config_atual.bip_time            <= 6'd5;
                config_atual.tranca_aut_time     <= 6'd5;
                config_atual.senha_master.digits <= 48'hFFFFFFFF1234;
                config_atual.senha_1.digits      <= {12{4'hF}};
                config_atual.senha_2.digits      <= {12{4'hF}};
                config_atual.senha_3.digits      <= {12{4'hF}};
                config_atual.senha_4.digits      <= {12{4'hF}};

                // Condição do Primeiro Reset
                if (sistema_inicializado) begin
                    state <= state_return; // Volta para o estado anterior
                end else begin
                    state                <= ST_FECHADA_TRANCADA; // Fallback se for o 1º absoluto
                    sistema_inicializado <= 1'b1; // Ativa o histórico para os próximos
                end
            end
            
            // RESET PARCIAL (Mínimo 5 segundos e menor que 10 segundos)
            else if (rst_timer >= T_5S) begin
                config_atual.senha_1.digits <= {12{4'hF}};
                config_atual.senha_2.digits <= {12{4'hF}};
                config_atual.senha_3.digits <= {12{4'hF}};
                config_atual.senha_4.digits <= {12{4'hF}};
                timer <= '0; // Reseta o timer para evitar múltiplos resets parciais em sequência

                if (sistema_inicializado) begin
                    state <= state_return;
                end else begin
                    state                <= ST_FECHADA_TRANCADA;
                    sistema_inicializado <= 1'b1;
                end
            end
            
            // CLIQUES CURTOS (Menor que 5 segundos): Totalmente Ignorados
            else begin
                if (!sistema_inicializado) begin
                    state                <= ST_FECHADA_TRANCADA;
                    sistema_inicializado <= 1'b1;
                end
                // Se já estava inicializado, não altera 'state' nem as configurações.
            end
        end
        
        // ------------------------------------------------------------------------
        // 3. OPERAÇÃO NORMAL DA FECHADURA (Botão Solto)
        // ------------------------------------------------------------------------
        else begin
            // Garante que se o circuito ligar e ninguém apertar o reset, ele inicializa correto
            if (!sistema_inicializado) begin
                state                <= ST_FECHADA_TRANCADA;
                state_return         <= ST_FECHADA_TRANCADA;
                sistema_inicializado <= 1'b1;
                
                // Carga inicial dos valores de fábrica ao ligar a placa
                config_atual.bip_status          <= 1'b1;
                config_atual.bip_time            <= 6'd5;
                config_atual.tranca_aut_time     <= 6'd5;
                config_atual.senha_master.digits <= 48'hFFFFFFFF1234;
                config_atual.senha_1.digits      <= {12{4'hF}};
                config_atual.senha_2.digits      <= {12{4'hF}};
                config_atual.senha_3.digits      <= {12{4'hF}};
                config_atual.senha_4.digits      <= {12{4'hF}};
            end

            // Atualiza registradores de borda dos botões comerciais
            botao_interno_prev  <= botao_interno;
            botao_config_prev   <= botao_config;
            botao_bloqueio_prev <= botao_bloqueio;

            // Atualiza configuração se o bloco de setup enviou novos dados
            if (data_setup_ok)
                config_atual <= data_setup_new;

            // Reseta o pulso do bip por padrão
            bip <= 1'b0;

            case (state)
                ST_FECHADA_TRANCADA: begin
                    tranca     <= 1'b1;
                    teclado_en <= 1'b1;
                    display_en <= 1'b0;
                    setup_on   <= 1'b0;
                    timer      <= '0;
                    bcd_pac    <= '0;

                    if (botao_interno_rise) begin
                        tranca <= 1'b0;
                        state  <= ST_FECHADA_DESTRANCADA;
                    end
                    else if (digitos_valid) begin
                        if (qualquer_senha_valida(digitos_value, config_atual)) begin
                            tranca <= 1'b0;
                            bip    <= 1'b1;
                            state  <= ST_FECHADA_DESTRANCADA;
                        end
                        else if (digitos_value.digits[0] == EVT_TIMEOUT || digitos_value.digits[0] == KEY_HASH || digitos_value.digits[0] == VAL_EMPTY) begin
                            bip   <= 1'b1;
                            state <= ST_FECHADA_TRANCADA;
                        end
                        else begin
                            bip   <= 1'b1;
                            state <= ST_ACESSO_NEGADO;
                        end
                    end
                end

                ST_FECHADA_DESTRANCADA: begin
                    tranca     <= 1'b0;
                    teclado_en <= 1'b1;
                    display_en <= 1'b0;

                    if (!sensor_contato) begin
                        timer <= '0;
                        state <= ST_ABERTA_DESTRANCADA;
                    end
                    else if (botao_interno_rise) begin
                        tranca <= 1'b1;
                        timer  <= '0;
                        state  <= ST_FECHADA_TRANCADA;
                    end
                    else begin
                        timer <= timer + 1'b1;
                        if (timer >= ({11'b0, config_atual.tranca_aut_time} * T_1S)) begin
                            tranca <= 1'b1;
                            timer  <= '0;
                            state  <= ST_FECHADA_TRANCADA;
                        end
                    end
                end

                ST_ABERTA_DESTRANCADA: begin
                    tranca     <= 1'b0;
                    teclado_en <= 1'b1;
                    display_en <= 1'b0;

                    if (botao_config_rise) begin
                        state <= ST_AUTENTICA_CONFIG;
                    end
                    else if (sensor_contato) begin
                        bip   <= 1'b0;
                        timer <= '0;
                        state <= ST_FECHADA_DESTRANCADA;
                    end
                    else begin
                        if (config_atual.bip_status) begin
                            timer <= timer + 1'b1;
                            if (timer >= ({11'b0, config_atual.bip_time} * T_1S)) begin
                                bip <= timer[8]; 
                            end
                        end
                    end
                end

                ST_ACESSO_NEGADO: begin
                    tranca     <= 1'b1;
                    teclado_en <= 1'b0;
                    display_en <= 1'b1;

                    bcd_pac <= '{BCD5: SEG_DASH, BCD4: SEG_DASH, BCD3: SEG_DASH,
                                 BCD2: SEG_DASH, BCD1: SEG_DASH, BCD0: SEG_DASH};

                    timer <= timer + 1'b1;
                    if (timer >= T_1S) begin
                        timer   <= '0;
                        bcd_pac <= '0;
                        state   <= ST_FECHADA_TRANCADA;
                    end
                end

                ST_BLOQUEADO: begin
                    state <= ST_FECHADA_TRANCADA;
                end

                ST_AUTENTICA_CONFIG: begin
                    tranca     <= 1'b0;
                    teclado_en <= 1'b1;
                    display_en <= 1'b0;
                    setup_on   <= 1'b0;
                    timer      <= '0;

                    if (digitos_valid) begin
                        if (senha_valida(digitos_value, config_atual.senha_master)) begin
                            bip   <= 1'b1;
                            state <= ST_MODO_CONFIG;
                        end
                        else if (digitos_value.digits[0] == EVT_TIMEOUT || digitos_value.digits[0] == KEY_HASH || digitos_value.digits[0] == VAL_EMPTY) begin
                            bip   <= 1'b1;
                            state <= ST_ABERTA_DESTRANCADA;
                        end
                        else begin
                            bip   <= 1'b1;
                        end
                    end
                end

                ST_MODO_CONFIG: begin
                    tranca     <= 1'b0;
                    teclado_en <= 1'b1;
                    display_en <= 1'b0;
                    setup_on   <= 1'b1;
                    timer      <= '0;

                    if (data_setup_ok) begin
                        setup_on <= 1'b0;
                        bip      <= 1'b1;
                        state    <= ST_ABERTA_DESTRANCADA;
                    end
                end

                default: state <= ST_FECHADA_TRANCADA;
            endcase
        end
    end
endmodule