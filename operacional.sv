// ============================================================================
// MÓDULO OPERACIONAL - FECHADURA ELETRÔNICA (OTIMIZADO)
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
        ST_TENTATIVA_LIBERADA,
        ST_AUTENTICA_CONFIG,
        ST_MODO_CONFIG,
        ST_NAO_PERTURBE
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

    wire botao_interno_rise;
    wire botao_config_rise;
    wire botao_bloqueio_rise;
    wire rst_fall;

    assign botao_interno_rise  = botao_interno  & ~botao_interno_prev;
    assign botao_config_rise   = botao_config   & ~botao_config_prev;
    assign botao_bloqueio_rise = botao_bloqueio & ~botao_bloqueio_prev;
    assign rst_fall            = rst_prev & ~rst;

    bit sistema_inicializado;

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

        // 1. GERENCIAMENTO DO RESET HARDWARE
        if (rst) begin
            if (rst_timer < 14'h3FFF) begin
                rst_timer <= rst_timer + 1'b1;
            end
            if (!rst_prev && sistema_inicializado) begin
                state_return <= state;
            end
        end

        else if (rst_fall) begin
            rst_timer    <= '0;
            state_timer  <= '0;
            hold_timer   <= '0;
            
            if (rst_timer >= T_10S) begin
                config_atual.bip_status          <= 1'b1;
                config_atual.bip_time            <= 6'd5;
                config_atual.tranca_aut_time     <= 6'd5;
                config_atual.senha_master.digits <= 48'hFFFFFFFF1234;
                config_atual.senha_1.digits      <= {12{4'hF}};
                config_atual.senha_2.digits      <= {12{4'hF}};
                config_atual.senha_3.digits      <= {12{4'hF}};
                config_atual.senha_4.digits      <= {12{4'hF}};
                cont_erros     <= '0;
                cont_bloqueios <= '0;
                state          <= sistema_inicializado ? state_return : ST_FECHADA_TRANCADA;
                sistema_inicializado <= 1'b1;
            end
            else if (rst_timer >= T_5S) begin
                config_atual.senha_1.digits <= {12{4'hF}};
                config_atual.senha_2.digits <= {12{4'hF}};
                config_atual.senha_3.digits <= {12{4'hF}};
                config_atual.senha_4.digits <= {12{4'hF}};
                cont_erros     <= '0;
                cont_bloqueios <= '0;
                state          <= sistema_inicializado ? state_return : ST_FECHADA_TRANCADA;
                sistema_inicializado <= 1'b1;
            end
            else if (!sistema_inicializado) begin
                state                            <= ST_FECHADA_TRANCADA;
                sistema_inicializado             <= 1'b1;
                config_atual.bip_status          <= 1'b1;
                config_atual.bip_time            <= 6'd5;
                config_atual.tranca_aut_time     <= 6'd5;
                config_atual.senha_master.digits <= 48'hFFFFFFFF1234;
                config_atual.senha_1.digits      <= {12{4'hF}};
                config_atual.senha_2.digits      <= {12{4'hF}};
                config_atual.senha_3.digits      <= {12{4'hF}};
                config_atual.senha_4.digits      <= {12{4'hF}};
                cont_erros     <= '0;
                cont_bloqueios <= '0;
            end
        end

        // 2. OPERAÇÃO NORMAL DA MALHA DE CONTROLE
        else begin
            if (!sistema_inicializado) begin
                state                <= ST_FECHADA_TRANCADA;
                state_return         <= ST_FECHADA_TRANCADA;
                sistema_inicializado <= 1'b1;
                hold_timer           <= '0;
                cont_erros           <= '0;
                cont_bloqueios       <= '0;
                state_timer          <= '0;
                inactivity_timer     <= '0;
                config_atual.bip_status          <= 1'b1;
                config_atual.bip_time            <= 6'd5;
                config_atual.tranca_aut_time     <= 6'd5;
                config_atual.senha_master.digits <= 48'hFFFFFFFF1234;
                config_atual.senha_1.digits      <= {12{4'hF}};
                config_atual.senha_2.digits      <= {12{4'hF}};
                config_atual.senha_3.digits      <= {12{4'hF}};
                config_atual.senha_4.digits      <= {12{4'hF}};
            end

            botao_interno_prev  <= botao_interno;
            botao_config_prev   <= botao_config;
            botao_bloqueio_prev <= botao_bloqueio;

            state_return <= state;
            if (data_setup_ok)
                config_atual <= data_setup_new;

            tranca     <= 1'b1;
            teclado_en <= 1'b0;
            display_en <= 1'b0;
            setup_on   <= 1'b0;
            bcd_pac    <= '0;
            bip        <= 1'b0;

            if (state_timer < 17'h1FFFF)      state_timer <= state_timer + 1'b1;
            if (inactivity_timer < 17'h1FFFF) inactivity_timer <= inactivity_timer + 1'b1;

            case (state)
                ST_FECHADA_TRANCADA: begin
                    tranca     <= 1'b1;
                    teclado_en <= 1'b1;

                    if (inactivity_timer >= T_60S) begin
                        cont_erros <= '0;
                    end

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
                                    cont_bloqueios   <= (cont_bloqueios < 3'd7) ? cont_bloqueios + 1'b1 : 3'd7;
                                    state_timer      <= '0;
                                    state            <= ST_BLOQUEADO;
                                end else begin
                                    cont_erros  <= cont_erros + 1'b1;
                                    state_timer <= '0;
                                    state       <= ST_ACESSO_NEGADO;
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
                    else if (botao_interno_rise || (state_timer >= ({11'b0, config_atual.tranca_aut_time} * T_1S))) begin
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
                    else if (config_atual.bip_status && (state_timer >= ({11'b0, config_atual.bip_time} * T_1S))) begin
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

                    if (state_timer >= T_1S) begin
                        state_timer <= '0;
                        state       <= ST_FECHADA_TRANCADA;
                    end
                end

                ST_BLOQUEADO: begin
                    display_en <= 1'b1;
                    bcd_pac    <= '{default: SEG_DASH};

                    if (state_timer >= ({11'b0, lockout_time_sec} * T_1S)) begin
                        state_timer      <= '0;
                        inactivity_timer <= '0;
                        state            <= ST_TENTATIVA_LIBERADA;
                    end
                end

                ST_TENTATIVA_LIBERADA: begin
                    teclado_en <= 1'b1;
                    bcd_pac    <= '{default: SEG_DASH};
                    display_en <= state_timer[8];

                    if (inactivity_timer >= T_60S) begin
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
                            cont_bloqueios <= (cont_bloqueios < 3'd7) ? cont_bloqueios + 1'b1 : 3'd7;
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
                    if (botao_interno_rise) begin
                        bip         <= 1'b1;
                        state_timer <= '0;
                        state       <= ST_FECHADA_DESTRANCADA;
                    end
                end

                default: state <= ST_FECHADA_TRANCADA;
            endcase
        end
    end

endmodule