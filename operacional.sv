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
        ST_TENTATIVA_LIBERADA,
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
    localparam int T_15S   = 15000;
    localparam int T_20S   = 20000;
    localparam int T_60S   = 60000;
    localparam int MAX_TIMER = 65535;

    // ==========================================
    // REGISTRADORES INTERNOS
    // ==========================================
    state_t    state;
    state_t    state_return;
    setupPac_t config_atual;

    logic [16:0] timer;
    logic [13:0] rst_timer;
    logic        rst_prev;

    // Contadores de erro e bloqueio
    logic [2:0] cont_erros;
    logic [2:0] cont_bloqueios;

    // Timers para controle de bloqueio e timeouts
    logic [16:0] lockout_timer;
    logic [16:0] tentativa_timer;
    logic [16:0] inactivity_timer;
    logic [5:0]  lockout_time_sec;

    // Controle de blink
    logic [9:0]  blink_counter;
    logic        blink_1hz;

    logic botao_interno_prev;
    logic botao_config_prev;
    logic botao_bloqueio_prev;

    wire botao_interno_rise  = botao_interno  & ~botao_interno_prev;
    wire botao_config_rise   = botao_config   & ~botao_config_prev;
    wire botao_bloqueio_rise = botao_bloqueio & ~botao_bloqueio_prev;

    bit sistema_inicializado;
    wire rst_fall = rst_prev & ~rst;

    // ==========================================
    // FUNÇÕES DE VALIDAÇÃO DE SENHA
    // ==========================================
    function automatic logic senha_valida(input digitosPac_t entrada, input senhaPac_t alvo);
        logic match;
        senha_valida = 1'b0;
        if (alvo.digits[3] == VAL_EMPTY) return 1'b0;
        for (int i = 0; i <= 19; i++) begin
            match = 1'b1;
            for (int j = 0; j < 12; j++) begin
                if (alvo.digits[j] != VAL_EMPTY) begin
                    if ((i + j) > 19 || entrada.digits[i + j] != alvo.digits[j])
                        match = 1'b0;
                end
            end
            if (match) return 1'b1;
        end
        return 1'b0;
    endfunction

    function automatic logic qualquer_senha_valida(input digitosPac_t entrada, input setupPac_t cfg);
        return senha_valida(entrada, cfg.senha_master) | senha_valida(entrada, cfg.senha_1) |
               senha_valida(entrada, cfg.senha_2)      | senha_valida(entrada, cfg.senha_3) |
               senha_valida(entrada, cfg.senha_4);
    endfunction

    // ============================================================================
    // FSM PRINCIPAL E LÓGICA DE RESET
    // ============================================================================
    always_ff @(posedge clk) begin
        rst_prev <= rst;

        if (rst) begin
            rst_timer <= (rst_timer < MAX_TIMER[13:0]) ? rst_timer + 1'b1 : MAX_TIMER[13:0];
            if (!rst_prev && sistema_inicializado) begin
                state_return <= state;
            end
        end
        else if (rst_fall) begin
            rst_timer <= '0;
            timer <= '0;
            if (rst_timer >= T_10S) begin // RESET TOTAL
                config_atual.bip_status          <= 1'b1;
                config_atual.bip_time            <= 6'd5;
                config_atual.tranca_aut_time     <= 6'd5;
                config_atual.senha_master.digits <= 48'hFFFFFFFF1234;
                config_atual.senha_1.digits      <= {12{4'hF}};
                config_atual.senha_2.digits      <= {12{4'hF}};
                config_atual.senha_3.digits      <= {12{4'hF}};
                config_atual.senha_4.digits      <= {12{4'hF}};
                cont_erros <= '0;
                cont_bloqueios <= '0';
            end else if (rst_timer >= T_5S) begin // RESET PARCIAL
                config_atual.senha_1.digits <= {12{4'hF}};
                config_atual.senha_2.digits <= {12{4'hF}};
                config_atual.senha_3.digits <= {12{4'hF}};
                config_atual.senha_4.digits <= {12{4'hF}};
                cont_erros <= '0;
                cont_bloqueios <= '0';
            end

            state <= sistema_inicializado ? state_return : ST_FECHADA_TRANCADA;
            if (!sistema_inicializado) sistema_inicializado <= 1'b1;
        end
        else begin // OPERAÇÃO NORMAL
            if (!sistema_inicializado) begin
                state                <= ST_FECHADA_TRANCADA;
                state_return         <= ST_FECHADA_TRANCADA;
                sistema_inicializado <= 1'b1;
                config_atual.bip_status          <= 1'b1;
                config_atual.bip_time            <= 6'd5;
                config_atual.tranca_aut_time     <= 6'd5;
                config_atual.senha_master.digits <= 48'hFFFFFFFF1234;
                config_atual.senha_1.digits      <= {12{4'hF}};
                config_atual.senha_2.digits      <= {12{4'hF}};
                config_atual.senha_3.digits      <= {12{4'hF}};
                config_atual.senha_4.digits      <= {12{4'hF}};
                cont_erros <= '0';
                cont_bloqueios <= '0';
            end

            botao_interno_prev  <= botao_interno;
            botao_config_prev   <= botao_config;
            botao_bloqueio_prev <= botao_bloqueio;

            if (data_setup_ok) config_atual <= data_setup_new;

            bip <= 1'b0;

            // Gerador de pulso 1Hz para piscar
            blink_counter <= blink_counter + 1;
            if(blink_counter == 500) blink_1hz <= ~blink_1hz;
            if(blink_counter >= 999) blink_counter <= 0;


            case (state)
                ST_FECHADA_TRANCADA: begin
                    tranca     <= 1'b1;
                    teclado_en <= 1'b1;
                    display_en <= 1'b0;
                    setup_on   <= 1'b0;
                    timer      <= '0;
                    bcd_pac    <= '0;

                    inactivity_timer <= inactivity_timer + 1;
                    if(inactivity_timer >= T_60S) begin
                        cont_erros <= 0;
                    end

                    if (botao_interno_rise) begin
                        tranca <= 1'b0;
                        cont_erros <= '0';
                        cont_bloqueios <= '0';
                        state  <= ST_FECHADA_DESTRANCADA;
                    end
                    else if (digitos_valid) begin
                        inactivity_timer <= 0; // Zera no evento do teclado
                        if (qualquer_senha_valida(digitos_value, config_atual)) begin
                            tranca <= 1'b0;
                            bip    <= 1'b1;
                            cont_erros <= '0';
                            cont_bloqueios <= '0';
                            state  <= ST_FECHADA_DESTRANCADA;
                        end
                        else if (digitos_value.digits[0] == EVT_TIMEOUT || digitos_value.digits[0] == KEY_HASH || digitos_value.digits[0] == VAL_EMPTY) begin
                            state <= ST_FECHADA_TRANCADA;
                        end
                        else begin // Senha inválida
                            bip   <= 1'b1;
                            cont_erros <= cont_erros + 1;
                            if(cont_erros < 5) begin
                                state <= ST_ACESSO_NEGADO;
                            end else begin
                                cont_bloqueios <= cont_bloqueios + 1;
                                state <= ST_BLOQUEADO;
                            end
                        end
                    end
                end

                ST_FECHADA_DESTRANCADA: begin
                    tranca     <= 1'b0;
                    teclado_en <= 1'b1;
                    display_en <= 1'b0;
                    cont_erros <= '0'; // Zera os erros ao conseguir abrir
                    cont_bloqueios <= '0'; // Zera os bloqueios

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
                            timer  <= '0';
                            state  <= ST_FECHADA_TRANCADA;
                        end
                    end
                end

                ST_ABERTA_DESTRANCADA: begin
                    tranca     <= 1'b0;
                    teclado_en <= 1'b1;
                    display_en <= 1'b0;
                    cont_erros <= '0'; // Zera os erros se abrir com botao interno
                    cont_bloqueios <= '0';

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

                    // Mostra traços de acordo com o número de erros
                    bcd_pac.BCD0 <= (cont_erros >= 1) ? SEG_DASH : VAL_EMPTY;
                    bcd_pac.BCD1 <= (cont_erros >= 2) ? SEG_DASH : VAL_EMPTY;
                    bcd_pac.BCD2 <= (cont_erros >= 3) ? SEG_DASH : VAL_EMPTY;
                    bcd_pac.BCD3 <= (cont_erros >= 4) ? SEG_DASH : VAL_EMPTY;
                    bcd_pac.BCD4 <= (cont_erros >= 5) ? SEG_DASH : VAL_EMPTY;
                    bcd_pac.BCD5 <= (cont_erros >= 5) ? SEG_DASH : VAL_EMPTY;

                    timer <= timer + 1'b1;
                    if (timer >= T_1S) begin
                        timer   <= '0;
                        bcd_pac <= '0;
                        state   <= ST_FECHADA_TRANCADA;
                    end
                end

                ST_BLOQUEADO: begin
                    tranca     <= 1'b1;
                    teclado_en <= 1'b0;
                    display_en <= 1'b1;
                    bcd_pac    <= '{default: SEG_DASH};

                    case(cont_bloqueios)
                        1: lockout_time_sec <= 5;
                        2: lockout_time_sec <= 10;
                        default: lockout_time_sec <= 20;
                    endcase

                    lockout_timer <= lockout_timer + 1;
                    if (lockout_timer >= lockout_time_sec * T_1S) begin
                        lockout_timer <= '0';
                        tentativa_timer <= '0';
                        inactivity_timer <= '0';
                        state <= ST_TENTATIVA_LIBERADA;
                    end
                end

                ST_TENTATIVA_LIBERADA: begin
                    tranca     <= 1'b1;
                    teclado_en <= 1'b1;

                    // Lógica de piscar
                    tentativa_timer <= tentativa_timer + 1;
                    if(tentativa_timer < T_15S) begin
                       display_en <= blink_1hz;
                       bcd_pac    <= '{default: SEG_DASH};
                    end else begin
                       display_en <= 1'b0; // Apaga após 15s
                    end

                    // Lógica de timeout de inatividade
                    inactivity_timer <= inactivity_timer + 1;
                    if (inactivity_timer >= (T_60S + lockout_time_sec * T_1S)) begin
                        cont_erros <= '0';
                        cont_bloqueios <= '0';
                        state <= ST_FECHADA_TRANCADA;
                    end

                    // Checa por eventos de cancelamento ou nova tentativa
                    if (botao_interno_rise) begin
                        tranca <= 1'b0;
                        cont_erros <= '0';
                        cont_bloqueios <= '0';
                        state <= ST_FECHADA_DESTRANCADA;
                    end else if (digitos_valid) begin
                        inactivity_timer <= 0; // Zera na tentativa
                        if (qualquer_senha_valida(digitos_value, config_atual)) begin
                            tranca <= 1'b0;
                            bip    <= 1'b1;
                            cont_erros <= '0';
                            cont_bloqueios <= '0';
                            state  <= ST_FECHADA_DESTRANCADA;
                        end else if (digitos_value.digits[0] != EVT_TIMEOUT && digitos_value.digits[0] != KEY_HASH && digitos_value.digits[0] != VAL_EMPTY) {
                            bip <= 1'b1;
                            cont_erros <= cont_erros + 1;
                            cont_bloqueios <= cont_bloqueios + 1;
                            lockout_timer <= '0';
                            state <= ST_BLOQUEADO;
                        }
                    end

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
                            bip   <= 1'b1; // Bipa no erro mas não conta para o bloqueio
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