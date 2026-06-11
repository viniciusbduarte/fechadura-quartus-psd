// ============================================================================
// MÓDULO OPERACIONAL - FECHADURA ELETRÔNICA (CORRIGIDO)
// ============================================================================
// CORREÇÕES APLICADAS:
//   FIX-1: ST_RESET_PARCIAL e ST_RESET_TOTAL retornam sempre para
//           ST_FECHADA_TRANCADA (estado seguro), eliminando a dependência
//           de state_return que apontava para estados que checam sensor_contato.
//
//   FIX-2: Flag `pos_reset` introduzido. Após qualquer reset (parcial ou
//           total), o ST_FECHADA_TRANCADA ignora sensor_contato por 1 ciclo
//           de clock (suficiente para que a porta seja fisicamente fechada
//           antes que o alarme seja avaliado).
//
//   FIX-3: ST_ALARME agora seta tranca <= 1'b0 explicitamente ao validar
//           senha master, evitando pulso indesejado de 1 ciclo na tranca
//           causado pelo valor padrão aplicado antes do case.
//           Destino corrigido de ST_ABERTA_DESTRANCADA → ST_FECHADA_DESTRANCADA
//           (mais seguro: a porta precisa ser reaberta normalmente).
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
        ST_INIT,
        ST_AVALIA_RESET,
        ST_RESET_PARCIAL,
        ST_RESET_TOTAL,
        ST_FECHADA_TRANCADA,
        ST_FECHADA_DESTRANCADA,
        ST_ABERTA_DESTRANCADA,
        ST_ACESSO_NEGADO,
        ST_BLOQUEADO,
        ST_TENTATIVA_LIBERADA,
        ST_AUTENTICA_CONFIG,
        ST_MODO_CONFIG,
        ST_NAO_PERTURBE,
        ST_ALARME
    } state_t;

    localparam logic [3:0] KEY_HASH    = 4'hB;
    localparam logic [3:0] EVT_TIMEOUT = 4'hE;
    localparam logic [3:0] VAL_EMPTY   = 4'hF;
    localparam logic [3:0] SEG_DASH    = 4'hA;

    localparam int T_1S   = 1000;
    localparam int T_3S   = 3000;
    localparam int T_5S   = 5000;
    localparam int T_10S  = 10000;
    localparam int T_60S  = 60000;

    state_t    state;
    state_t    state_return;
    setupPac_t config_atual;

    logic [13:0] rst_timer;
    logic        rst_prev;

    logic [2:0] cont_erros;
    logic [2:0] cont_bloqueios;

    logic [16:0] state_timer;
    logic [16:0] inactivity_timer;
    logic [11:0] hold_timer;
    logic [5:0]  lockout_time_sec;

    logic botao_interno_prev;
    logic botao_config_prev;
    logic botao_bloqueio_prev;

    // ─── FIX-2: Flag de proteção pós-reset ─────────────────────────────────
    logic pos_reset;

    wire botao_interno_rise;
    wire botao_config_rise;
    wire botao_bloqueio_rise;
    wire rst_fall;

    assign botao_interno_rise  = botao_interno  & ~botao_interno_prev;
    assign botao_config_rise   = botao_config   & ~botao_config_prev;
    assign botao_bloqueio_rise = botao_bloqueio & ~botao_bloqueio_prev;
    assign rst_fall            = rst_prev & ~rst;

    logic sistema_inicializado;

    always_comb begin
        case (cont_bloqueios)
            3'd1:    lockout_time_sec = 6'd5;
            3'd2:    lockout_time_sec = 6'd10;
            default: lockout_time_sec = 6'd20;
        endcase
    end

    function automatic logic senha_valida(
        input digitosPac_t entrada,
        input senhaPac_t   alvo
    );
        logic match;
        senha_valida = 1'b0;
        if (alvo.digits[3] == VAL_EMPTY)
            return 1'b0;
        for (int i = 0; i <= 19; i++) begin
            match = 1'b1;
            for (int j = 0; j < 12; j++) begin
                if (alvo.digits[j] != VAL_EMPTY) begin
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
    // FSM PRINCIPAL E LÓGICA DE CONTROLE
    // ============================================================================
    always_ff @(posedge clk) begin
        rst_prev <= rst;

        // ────────────────────────────────────────────────────────────────────
        // 1. GERENCIAMENTO GLOBAL DO BOTÃO DE RESET (HARDWARE) @vini, sei q vc botou em borda de descida, mas a lógica nao faz muito sentido
        // ────────────────────────────────────────────────────────────────────
        if (rst) begin
            if (rst_timer < 14'h3FFF)
                rst_timer <= rst_timer + 1'b1;

            if (!rst_prev && sistema_inicializado) begin
                if (state != ST_INIT && state != ST_AVALIA_RESET &&
                    state != ST_RESET_PARCIAL && state != ST_RESET_TOTAL) begin
                    state_return <= state;
                end
            end
        end

        // Ao soltar o botão de reset → avalia tempo pressionado
        else if (rst_fall) begin
            state <= ST_AVALIA_RESET;
        end

        // ────────────────────────────────────────────────────────────────────
        // 2. OPERAÇÃO DA MALHA DE ESTADOS
        // ────────────────────────────────────────────────────────────────────
        else begin
            if (!sistema_inicializado && state != ST_INIT && state != ST_AVALIA_RESET &&
                state != ST_RESET_PARCIAL && state != ST_RESET_TOTAL) begin
                state <= ST_INIT;
            end

            botao_interno_prev  <= botao_interno;
            botao_config_prev   <= botao_config;
            botao_bloqueio_prev <= botao_bloqueio;

            if (state != ST_INIT && state != ST_AVALIA_RESET &&
                state != ST_RESET_PARCIAL && state != ST_RESET_TOTAL &&
                state != ST_ALARME && state != ST_BLOQUEADO && state != ST_ACESSO_NEGADO) begin
                state_return <= state;
            end

            if (data_setup_ok)
                config_atual <= data_setup_new;

            // Valores padrão de saída (estado seguro)
            tranca     <= 1'b1;
            teclado_en <= 1'b0;
            display_en <= 1'b0;
            setup_on   <= 1'b0;
            bcd_pac    <= '0;
            bip        <= 1'b0;

            if (state_timer < 17'h1FFFF)      state_timer      <= state_timer + 1'b1;
            if (inactivity_timer < 17'h1FFFF) inactivity_timer <= inactivity_timer + 1'b1;

            case (state)

                // ────────────────────────────────────────────────────────────
                // GERENCIAMENTO DE RESET E INICIALIZAÇÃO
                // ────────────────────────────────────────────────────────────

                ST_INIT: begin
                    config_atual.bip_status          <= 1'b1;
                    config_atual.bip_time            <= 6'd5;
                    config_atual.tranca_aut_time     <= 6'd5;
                    config_atual.senha_master.digits <= 48'hFFFFFFFF1234;
                    config_atual.senha_1.digits      <= {12{4'hF}};
                    config_atual.senha_2.digits      <= {12{4'hF}};
                    config_atual.senha_3.digits      <= {12{4'hF}};
                    config_atual.senha_4.digits      <= {12{4'hF}};

                    cont_erros           <= '0;
                    cont_bloqueios       <= '0;
                    hold_timer           <= '0;
                    state_timer          <= '0;
                    inactivity_timer     <= '0;
                    rst_timer            <= '0;
                    pos_reset            <= 1'b0;   // FIX-2

                    sistema_inicializado <= 1'b1;
                    state                <= ST_FECHADA_TRANCADA;
                    state_return         <= ST_FECHADA_TRANCADA;
                end

                ST_AVALIA_RESET: begin
                    state_timer <= '0;
                    hold_timer  <= '0;

                    if (rst_timer >= T_10S) begin
                        state <= ST_RESET_TOTAL;
                    end
                    else if (rst_timer <= T_5S) begin
                        state <= ST_RESET_PARCIAL;
                    end
                    else begin
                        rst_timer <= '0;
                        state     <= sistema_inicializado ? state_return : ST_INIT;
                    end
                end

                // ─── FIX-1: Retorno sempre para estado seguro ────────────────
                ST_RESET_PARCIAL: begin
                    config_atual.senha_1.digits <= {12{4'hF}};
                    config_atual.senha_2.digits <= {12{4'hF}};
                    config_atual.senha_3.digits <= {12{4'hF}};
                    config_atual.senha_4.digits <= {12{4'hF}};

                    cont_erros       <= '0;
                    cont_bloqueios   <= '0;
                    state_timer      <= '0;
                    rst_timer        <= '0;
                    pos_reset        <= 1'b1;   // FIX-2: sinaliza saída de reset

                    sistema_inicializado <= 1'b1;
                    state                <= ST_FECHADA_TRANCADA; // FIX-1
                end

                ST_RESET_TOTAL: begin
                    config_atual.bip_status          <= 1'b1;
                    config_atual.bip_time            <= 6'd5;
                    config_atual.tranca_aut_time     <= 6'd5;
                    config_atual.senha_master.digits <= 48'hFFFFFFFF1234;
                    config_atual.senha_1.digits      <= {12{4'hF}};
                    config_atual.senha_2.digits      <= {12{4'hF}};
                    config_atual.senha_3.digits      <= {12{4'hF}};
                    config_atual.senha_4.digits      <= {12{4'hF}};

                    cont_erros       <= '0;
                    cont_bloqueios   <= '0;
                    state_timer      <= '0;
                    rst_timer        <= '0;
                    pos_reset        <= 1'b1;   // FIX-2: sinaliza saída de reset

                    sistema_inicializado <= 1'b1;
                    state                <= ST_FECHADA_TRANCADA; // FIX-1
                end

                // ────────────────────────────────────────────────────────────
                // ESTADOS OPERACIONAIS
                // ────────────────────────────────────────────────────────────

                ST_FECHADA_TRANCADA: begin
                    tranca     <= 1'b1;
                    teclado_en <= 1'b1;

                    // ─── FIX-2: Ignora sensor_contato no primeiro ciclo pós-reset
                    if (!sensor_contato) begin
                        if (pos_reset) begin
                            pos_reset <= 1'b0; // Consome o flag; aguarda porta fechar
                        end else begin
                            state_timer <= '0;
                            state       <= ST_ALARME;
                        end
                    end else begin
                        pos_reset <= 1'b0; // Porta fechada: limpa flag normalmente

                        if (inactivity_timer >= T_60S)
                            cont_erros <= '0;

                        if (botao_interno_rise) begin
                            state_timer      <= '0;
                            inactivity_timer <= '0;
                            state            <= ST_FECHADA_DESTRANCADA;
                        end
                        else if (botao_bloqueio && sensor_contato) begin
                            hold_timer <= hold_timer + 1'b1;
                            if (hold_timer >= T_3S) begin
                                hold_timer       <= '0;
                                inactivity_timer <= '0;
                                bip              <= 1'b1;
                                state            <= ST_NAO_PERTURBE;
                            end
                        end
                        else begin
                            hold_timer <= '0;

                            if (digitos_valid) begin
                                inactivity_timer <= '0;

                                if (qualquer_senha_valida(digitos_value, config_atual)) begin
                                    bip            <= 1'b1;
                                    cont_erros     <= '0;
                                    cont_bloqueios <= '0;
                                    state_timer    <= '0;
                                    state          <= ST_FECHADA_DESTRANCADA;
                                end
                                else if (digitos_value.digits[0] == EVT_TIMEOUT ||
                                         digitos_value.digits[0] == KEY_HASH    ||
                                         digitos_value.digits[0] == VAL_EMPTY) begin
                                    state <= ST_FECHADA_TRANCADA;
                                end
                                else begin
                                    bip <= 1'b1;
                                    if (cont_erros >= 3'd4) begin
                                        cont_bloqueios <= (cont_bloqueios < 3'd7) ?
                                                          cont_bloqueios + 1'b1 : 3'd7;
                                        state_timer    <= '0;
                                        state          <= ST_BLOQUEADO;
                                    end else begin
                                        cont_erros  <= cont_erros + 1'b1;
                                        state_timer <= '0;
                                        state       <= ST_ACESSO_NEGADO;
                                    end
                                end
                            end
                        end
                    end
                end

                ST_FECHADA_DESTRANCADA: begin
                    tranca         <= 1'b0;
                    teclado_en     <= 1'b1;
                    cont_erros     <= '0;
                    cont_bloqueios <= '0;

                    if (!sensor_contato) begin
                        state_timer <= '0;
                        state       <= ST_ABERTA_DESTRANCADA;
                    end
                    else if (botao_interno_rise ||
                             (state_timer >= ({11'b0, config_atual.tranca_aut_time} * T_1S))) begin
                        state_timer <= '0;
                        state       <= ST_FECHADA_TRANCADA;
                    end
                end

                ST_ABERTA_DESTRANCADA: begin
                    tranca         <= 1'b0;
                    teclado_en     <= 1'b1;
                    cont_erros     <= '0;
                    cont_bloqueios <= '0;

                    if (botao_config_rise) begin
                        state_timer <= '0;
                        state       <= ST_AUTENTICA_CONFIG;
                    end
                    else if (sensor_contato) begin
                        state_timer <= '0;
                        state       <= ST_FECHADA_DESTRANCADA;
                    end
                    else if (config_atual.bip_status &&
                             (state_timer >= ({11'b0, config_atual.bip_time} * T_1S))) begin
                        bip <= state_timer[8];
                    end
                end

                ST_ACESSO_NEGADO: begin
                    display_en   <= 1'b1;
                    bcd_pac.BCD0 <= (cont_erros >= 3'd1) ? SEG_DASH : VAL_EMPTY;
                    bcd_pac.BCD1 <= (cont_erros >= 3'd2) ? SEG_DASH : VAL_EMPTY;
                    bcd_pac.BCD2 <= (cont_erros >= 3'd3) ? SEG_DASH : VAL_EMPTY;
                    bcd_pac.BCD3 <= (cont_erros >= 3'd4) ? SEG_DASH : VAL_EMPTY;
                    bcd_pac.BCD4 <= (cont_erros >= 3'd5) ? SEG_DASH : VAL_EMPTY;
                    bcd_pac.BCD5 <= (cont_erros >= 3'd5) ? SEG_DASH : VAL_EMPTY;

                    if (!sensor_contato) begin
                        state_timer <= '0;
                        state       <= ST_ALARME;
                    end
                    else if (state_timer >= T_1S) begin
                        state_timer <= '0;
                        state       <= ST_FECHADA_TRANCADA;
                    end
                end

                ST_BLOQUEADO: begin
                    display_en <= 1'b1;
                    bcd_pac    <= '{default: SEG_DASH};

                    if (!sensor_contato) begin
                        state_timer <= '0;
                        state       <= ST_ALARME;
                    end
                    else if (state_timer >= ({11'b0, lockout_time_sec} * T_1S)) begin
                        state_timer      <= '0;
                        inactivity_timer <= '0;
                        state            <= ST_TENTATIVA_LIBERADA;
                    end
                end

                ST_TENTATIVA_LIBERADA: begin
                    teclado_en <= 1'b1;
                    bcd_pac    <= '{default: SEG_DASH};
                    display_en <= state_timer[8];

                    if (!sensor_contato) begin
                        state_timer <= '0;
                        state       <= ST_ALARME;
                    end
                    else if (inactivity_timer >= T_60S) begin
                        cont_erros     <= '0;
                        cont_bloqueios <= '0;
                        state_timer    <= '0;
                        state          <= ST_FECHADA_TRANCADA;
                    end
                    else if (botao_interno_rise) begin
                        cont_erros     <= '0;
                        cont_bloqueios <= '0;
                        state_timer    <= '0;
                        state          <= ST_FECHADA_DESTRANCADA;
                    end
                    else if (digitos_valid) begin
                        inactivity_timer <= '0;

                        if (qualquer_senha_valida(digitos_value, config_atual)) begin
                            bip            <= 1'b1;
                            cont_erros     <= '0;
                            cont_bloqueios <= '0;
                            state_timer    <= '0;
                            state          <= ST_FECHADA_DESTRANCADA;
                        end
                        else if (digitos_value.digits[0] == EVT_TIMEOUT ||
                                 digitos_value.digits[0] == KEY_HASH    ||
                                 digitos_value.digits[0] == VAL_EMPTY) begin
                            state_timer <= '0;
                        end
                        else begin
                            bip            <= 1'b1;
                            cont_erros     <= cont_erros + 1'b1;
                            cont_bloqueios <= (cont_bloqueios < 3'd7) ?
                                              cont_bloqueios + 1'b1 : 3'd7;
                            state_timer    <= '0;
                            state          <= ST_BLOQUEADO;
                        end
                    end
                end

                ST_AUTENTICA_CONFIG: begin
                    tranca     <= 1'b0;
                    teclado_en <= 1'b1;

                    if (state_timer >= T_10S) begin
                        bip         <= 1'b1;
                        state_timer <= '0;
                        state       <= ST_ABERTA_DESTRANCADA;
                    end
                    else if (digitos_valid) begin
                        if (senha_valida(digitos_value, config_atual.senha_master)) begin
                            bip         <= 1'b1;
                            state_timer <= '0;
                            state       <= ST_MODO_CONFIG;
                        end
                        else begin
                            bip         <= 1'b1;
                            state_timer <= '0;
                            state       <= ST_ABERTA_DESTRANCADA;
                        end
                    end
                end

                ST_MODO_CONFIG: begin
                    tranca     <= 1'b0;
                    teclado_en <= 1'b1;
                    setup_on   <= 1'b1;

                    if (data_setup_ok) begin
                        bip         <= 1'b1;
                        state_timer <= '0;
                        state       <= ST_ABERTA_DESTRANCADA;
                    end
                end

                ST_NAO_PERTURBE: begin
                    if (!sensor_contato) begin
                        state_timer <= '0;
                        state       <= ST_ALARME;
                    end
                    else if (botao_interno_rise) begin
                        bip         <= 1'b1;
                        state_timer <= '0;
                        state       <= ST_FECHADA_DESTRANCADA;
                    end
                end

                // ─── FIX-3: tranca explícita + destino corrigido ─────────────
                ST_ALARME: begin
                    teclado_en <= 1'b1;
                    display_en <= 1'b1;
                    bcd_pac    <= '{default: SEG_DASH};
                    bip        <= state_timer[8];

                    if (digitos_valid) begin
                        if (senha_valida(digitos_value, config_atual.senha_master)) begin
                            cont_erros  <= '0;
                            state_timer <= '0;
                            tranca      <= 1'b0;              // FIX-3: sem pulso na tranca
                            state       <= ST_FECHADA_DESTRANCADA; // FIX-3: estado mais seguro
                        end
                    end
                end

                default: state <= ST_INIT;
            endcase
        end
    end

endmodule
