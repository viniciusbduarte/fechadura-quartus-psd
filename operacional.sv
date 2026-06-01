// ============================================================================
// MÓDULO OPERACIONAL - FECHADURA ELETRÔNICA
// ============================================================================
// O módulo Operacional é responsável por executar todo o comportamento funcional 
// da fechadura eletrônica.
// ============================================================================
import projeto_types::*; // Importa os tipos do pacote

module operacional(
	input		logic		    clk,                //
	input		logic		    rst,                //
	input		logic		    sensor_contato,     //
	input		logic		    botao_interno,
	input		logic		    botao_bloqueio,
	input		logic		    botao_config,
	input		setupPac_t 	    data_setup_new,
	input		logic		    data_setup_ok,
	input		digitosPac_t	digitos_value,
	input		logic		    digitos_valid,
	output		bcdPac_t	    bcd_pac,
	output 		logic 		    teclado_en,
	output		logic		    display_en,
	output		logic		    setup_on,
	output		logic		    tranca,
	output		logic		    bip
);

    // ==========================================
    // DEFINIÇÕES DE ESTADO DA FSM (9 MENUS + IDLE/COMMIT)
    // ==========================================
    typedef enum logic [3:0] {
        ST_CLOSED_LOCKED,   //Indica que a porta está fechada trancada           
        ST_CLOSED_UNLOCKED, //Indica que a porta está fechada destrancada     
        ST_OPEN_UNLOCKED,   //Indica que a porta está aberta destrancada    
        ST_VERIFY,          //Verifica a senha digitada
        ST_BLOCK_OUTSIDE,   //Indica que o botão de bloqueio foi pressionado e a porta está bloqueada externamente
        ST_BLOCK_KEYBOARD,  //A senha foi invalida e o teclado está bloqueado  
        ST_BIP_ON,          //Bip está ativo, alertando algo ao usuário
        ST_RESET_TOTAL,     //Reseta todos os dados para padrão de fábrica
        ST_RESET_PARCIAL,   //Reseta as senhas (menos a senha_master) para padrão de fábrica
        ST_SETUP_AUTH,      //Apertei botão de config verifica se a senha master ta ok pra entrar no setup
        ST_SETUP_MODE,      //Quando entrar no setup
    } state_t;

    state_t state;            // Registrador que armazena o estado atual da FSM
    setupPac_t draft_config;  // Registrador temporário (rascunho) para guardar dados recebidos pelo data_setup_new
    logic        timer_tranca_aut_done; // Sinal que avisa a FSM que o tempo acabou
    logic        timer_tranca_en;   // Sinal que a FSM usa para ligar o timer
    logic [12:0] counter_aut_lock;  // Contador de ciclos
     

    // ==========================================
    // DEFINIÇÕES DE VALORES ESPECIAIS DO TECLADO
    // ==========================================
    localparam logic [3:0] KEY_HASH    = 4'hB; // Tecla '#': Aborta operação imediata no setup ou apagada digitos_value
    localparam logic [3:0] EVT_TIMEOUT = 4'hE; // Evento de estouro de tempo (Deve ser totalmente ignorado aqui)
    localparam logic [3:0] VAL_EMPTY   = 4'hF; // Código que representa ausência de dígito pressionado (Vazio)

    // Sinal combinacional que fica em '1' se a senha digitada bater com qualquer senha válida
    logic senha_correta;

    // Assumindo que "data_setup_new" contém as senhas salvas 
    // e "digitos_value" contém a senha formatada digitada.
    assign senha_correta = (digitos_value == data_setup_new.senha_master) ||
                        (digitos_value == data_setup_new.senha_1)      ||
                        (digitos_value == data_setup_new.senha_2)      ||
                        (digitos_value == data_setup_new.senha_3)      ||
                        (digitos_value == data_setup_new.senha_4);

    // Variável para contar os erros (precisa ser declarada junto com os outros 'logic')
    logic [2:0] tentativas_falhas; // Conta até 7, suficiente para o limite de erros

    //Nota: O código do assign acima é conceitual. Você precisará ajustar os nomes exatos de .senha_master, etc.,
    // conforme definidos dentro da sua struct setupPac_t,quais são esses nomes??

//timer_tranca_en: É uma saída da sua FSM (controlada dentro do case). Ela diz ao contador: "Ei, comece a contar agora!".

//always_ff do contador: Fica escutando o clock. Se o "enable" estiver ligado, ele conta. Se não, ele zera.

//timer_tranca_aut_done: É uma entrada para a sua FSM. A FSM fica "olhando" para esse sinal dentro do estado 
//ST_CLOSED_UNLOCKED. Quando ele virar 1, a FSM sabe que é hora de mudar de estado e pular para o ST_CLOSED_LOCKED.

    always_ff @(posedge clk) begin
        if (rst) begin
            counter_aut_lock      <= '0;
            timer_tranca_aut_done <= 1'b0;
        end else begin
            if (timer_tranca_en) begin
                // 5000 ciclos = 5 segundos a 1kHz
                if (counter_aut_lock >= 13'd5000) begin 
                    timer_tranca_aut_done <= 1'b1;
                end else begin
                    counter_aut_lock      <= counter_aut_lock + 1'b1;
                    timer_tranca_aut_done <= 1'b0;
                end
            end else begin
                // Se o timer não está habilitado, zera tudo
                counter_aut_lock      <= '0;
                timer_tranca_aut_done <= 1'b0;
            end
        end
    end
    // ==========================================
    // MÁQUINA DE ESTADOS SEQUENCIAL (FSM)
    //essa primeira parte do always ff antes do case veio do setup, muito provavelmente precisara alterações
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
                
                // ESTADO PORTA FECHADA E TRANCADA
                ST_CLOSED_LOCKED: begin
                    // 1. Manutenção das Saídas (Garantindo o estado seguro)
                    tranca     <= 1'b1; // Tranca fechada 
                    teclado_en <= 1'b1; // Teclado habilitado aguardando senha
                    display_en <= 1'b0; // Displays apagados em operação normal
                    bip        <= 1'b0; // Bip desativado
                    setup_on   <= 1'b0; // Setup não pode ser ativado com porta fechada/trancada

                    // 2. Análise de Transições (Prioridade de roteamento)
                    
                    // Prioridade 1: Botão interno (Saída rápida)
                    if (botao_interno) begin
                        tranca <= 1'b0; // Abre a tranca imediatamente 
                        state  <= ST_CLOSED_UNLOCKED; 
                    end
                    
                    // Prioridade 2: Ativação do "Não Perturbe"
                    // Nota: Recomenda-se um contador paralelo (ex: timer_3s_done) para medir os 3 seg.
                    else if (botao_bloqueio && timer_3s_done) begin
                        state <= ST_BLOCK_OUTSIDE; // Muda para o estado que ignora o teclado externo
                    end
                    
                    // Prioridade 3: Usuário digitando no teclado
                    else if (digitos_valid) begin
                        // O sistema recebeu uma entrada válida do teclado 
                        // Se a tecla '*' for pressionada (depende de como o teclado sinaliza o fim),
                        // ou se o sistema deve validar a cada tecla inserida, vamos para a verificação.
                        state <= ST_VERIFY; // Vai para o estado que processa e valida a senha 
                    end
                    
                    // Prioridade 4 (Opcional, mas boa prática): Detecção de violação
                    else if (sensor_contato == 1'b0) begin
                        // Porta violada! Aqui poderia ir para um ST_ALARM, mas como não 
                        // está explícito, mantemos monitoramento.
                        // Se o sensor indicar que a porta abriu sem a tranca destravar
                    end
                end

                ST_CLOSED_UNLOCKED: begin
                    // 1. Configuração das Saídas para o Estado Destravado
                    tranca         <= 1'b0; // Destrava o mecanismo físico
                    teclado_en     <= 1'b0; // Desabilita o teclado (operação de entrada concluída)
                    display_en     <= 1'b1; // Ativa display (pode mostrar que a porta está aberta/livre)
                    bip            <= 1'b0;
                    setup_on       <= 1'b0;

                    // Habilita o temporizador de travamento automático apenas enquanto estiver neste estado
                    timer_tranca_en <= 1'b1; 

                    // 2. Lógica de Transições de Estado (Prioridade)

                    // Regra 1: Se a porta for aberta fisicamente
                    // (Considerando que sensor_contato == 1'b1 significa FECHADA e 1'b0 significa ABERTA)
                    if (sensor_contato == 1'b0) begin
                        timer_tranca_en <= 1'b0; // Desliga o timer de travamento
                        state           <= ST_OPEN; // Vai para o estado de monitoramento de porta aberta
                    end

                    // Regra 2: Se o botão de configuração for pressionado
                    else if (botao_config) begin
                        timer_tranca_en <= 1'b0;
                        setup_on        <= 1'b1; // Ativa o módulo de Setup
                        state           <= ST_SETUP_MODE; // Transiciona para o estado gerenciado pelo Setup
                    end

                    // Regra 3: O usuário não abriu a porta e o tempo de travamento automático acabou
                    else if (timer_tranca_aut_done) begin
                        timer_tranca_en <= 1'b0;
                        state           <= ST_CLOSED_LOCKED; // Tranca novamente de forma automática
                    end
                end

                ST_OPEN_UNLOCKED: begin
                    // 1. Configuração das Saídas (Segurança Mecânica)
                    tranca          <= 1'b0; // Garante pino recolhido para não danificar o batente
                    teclado_en      <= 1'b0; // Teclado inativo para senhas
                    display_en      <= 1'b1; // Display ativo (pode exibir um indicativo visual)
                    bip             <= 1'b0;
                    setup_on        <= 1'b0;
                    
                    // DESLIGA o timer de travamento automático! 
                    // Ele só deve contar quando a porta estiver fechada.
                    timer_tranca_en <= 1'b0; 

                    // 2. Lógica de Transições de Estado

                    // Prioridade 1: Botão de Configuração pressionado
                    // (A porta aberta é o momento mais seguro para cadastrar novas senhas)
                    if (botao_config) begin
                        setup_on <= 1'b1;         // Liga a flag que acorda o módulo de SETUP
                        state    <= ST_SETUP_MODE; // Vai para o estado que aguarda o Setup finalizar
                    end
                    
                    // Prioridade 2: O usuário empurrou a porta e ela fechou
                    // (Assumindo que sensor_contato == 1'b1 significa porta fisicamente fechada)
                    else if (sensor_contato == 1'b1) begin
                        // Retorna para o estado "Fechada e Destravada". 
                        // A transição para esse estado ligará o timer_tranca_en automaticamente
                        // no próximo ciclo de clock, cumprindo a regra de travamento automático
                        state <= ST_CLOSED_UNLOCKED; 
                    end
                end

                ST_VERIFY: begin
                    // 1. Configurações de Segurança
                    tranca     <= 1'b1; // Mantém trancada
                    teclado_en <= 1'b0; // Pausa a leitura do teclado
                    bip        <= 1'b0;
                    setup_on   <= 1'b0;

                    // 2. Lógica de Decisão
                    if (senha_correta) begin
                        // Sucesso!
                        tentativas_falhas <= '0;               // Zera as tentativas erradas
                        state             <= ST_CLOSED_UNLOCKED; // Vai para o estado que destrava a porta
                    end 
                    else begin
                        // Falha!
                        // Verifica se já estourou o limite de erros (Ex: 3 tentativas totais)
                        // Se `tentativas_falhas` era 2, esse é o 3º erro consecutivo.
                        if (tentativas_falhas >= 3'd2) begin 
                            tentativas_falhas <= '0;          // Prepara o contador para o futuro
                            state             <= ST_PENALTY;  // Vai para o estado de bloqueio/alarme
                        end else begin
                            tentativas_falhas <= tentativas_falhas + 1'b1; // Incrementa o erro
                            state             <= ST_CLOSED_LOCKED;         // Volta a aguardar nova senha
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


