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

    // Novas variáveis do Temporizador Genérico, temporizador adaptado para uso de um unico registrador para 
    //todos os estados que usam temporizador, mas se necessário podemos fazer varios always_ff para cada estado
    //que utiluza temporizador, o que acha? @vinicius
    // timer_limit: É uma saída da sua FSM. Ela diz ao contador genérico: "Ei, conte exatamente até ESSE valor!". 
    // Em vez de ser um tempo fixo, a FSM escolhe na hora se quer 3000 ciclos (3 segundos) ou 5000 ciclos (5 segundos).

    // timer_en: É uma saída da sua FSM (controlada dentro do case). Ela diz ao contador: "Ei, comece a contar agora!". 
    // Enquanto estiver em '1', o contador sobe. Se a FSM colocar em '0', o contador para e zera imediatamente.

    // timer_done: É uma entrada para a sua FSM (o contador responde para a FSM). A FSM fica "olhando" para esse sinal 
    // dentro de estados como ST_CLOSED_UNLOCKED ou ST_CLOSED_LOCKED. Quando ele virar '1', a FSM sabe que o tempo 
    // que ela pediu no timer_limit acabou, e então ela executa a mudança de estado.

    // counter_gen: (Extra) É a variável interna do bloco always_ff do temporizador. É o cronômetro físico em si. 
    // A FSM nunca precisa olhar para ele diretamente, ela só olha para o "timer_done".
    logic [12:0] timer_limit;  // A FSM diz qual é o limite (3000 ou 5000)
    logic        timer_en;     // A FSM manda ligar
    logic        timer_done;   // O contador avisa que acabou
    logic [12:0] counter_gen;  // O contador em si
     

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
    // conforme definidos dentro da sua struct setupPac_t,quais são esses nomes?? @vinicius

//timer_tranca_en: É uma saída da sua FSM (controlada dentro do case). Ela diz ao contador: "Ei, comece a contar agora!".

//always_ff do contador: Fica escutando o clock. Se o "enable" estiver ligado, ele conta. Se não, ele zera.

//timer_tranca_aut_done: É uma entrada para a sua FSM. A FSM fica "olhando" para esse sinal dentro do estado 
//ST_CLOSED_UNLOCKED. Quando ele virar 1, a FSM sabe que é hora de mudar de estado e pular para o ST_CLOSED_LOCKED.

    // ÚNICO bloco contador do sistema
    always_ff @(posedge clk) begin
        if (rst) begin
            state             <= ST_RESET_TOTAL; // Agora o ponto de partida é aqui!
            tentativas_falhas <= '0;
            timer_en          <= 1'b0;
            tranca            <= 1'b1;           // Inicia trancada por segurança
            counter_gen <= '0;
            timer_done  <= 1'b0;
        //end else if (rst_parcial) begin
        //    state <= ST_RESET_PARCIAL; //esse bloco se faz necessário? @vinicius
        end else begin
            if (timer_en) begin
                if (counter_gen >= timer_limit) begin 
                    timer_done <= 1'b1; // Bateu no limite que a FSM escolheu!
                end else begin
                    counter_gen <= counter_gen + 1'b1;
                    timer_done  <= 1'b0;
                end
            end else begin
                // Se o timer for desligado pela FSM, limpa os registradores
                counter_gen <= '0;
                timer_done  <= 1'b0;
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
                    tranca     <= 1'b1; 
                    teclado_en <= 1'b1; 
                    display_en <= 1'b0; 
                    bip        <= 1'b0; 
                    setup_on   <= 1'b0; 

                    // Lógica do Botão de Bloqueio (Não Perturbe - 3 segundos)
                    if (botao_bloqueio) begin
                        timer_limit <= 13'd3000; // Define o limite para 3 segundos (3000 ciclos a 1kHz)
                        timer_en    <= 1'b1;    // Manda o timer começar a contar
                        
                        if (timer_done) begin
                            timer_en <= 1'b0;            // Desliga o timer antes de mudar de estado
                            state    <= ST_BLOCK_OUTSIDE; // Vai para o modo Não Perturbe
                        end
                    end else begin
                        // Se o usuário não está apertando o botão (ou soltou no meio do caminho), garante o timer desligado
                        timer_en <= 1'b0;
                        
                        // Mantém as outras transições normais do estado...
                        if (botao_interno) begin
                            state <= ST_CLOSED_UNLOCKED;
                        end 
                        else if (digitos_valid) begin
                            state <= ST_VERIFY;
                        end
                    end
                end

                ST_CLOSED_UNLOCKED: begin
                    tranca     <= 1'b0; // Destrava a porta
                    teclado_en <= 1'b0; 
                    display_en <= 1'b1; 
                    bip        <= 1'b0;
                    setup_on   <= 1'b0;

                    // Configura o timer para o Travamento Automático (5 segundos)
                    timer_limit <= 13'd5000; // Define o limite para 5 segundos (5000 ciclos a 1kHz)
                    timer_en    <= 1'b1;    // Ativa a contagem

                    // Transições
                    if (sensor_contato == 1'b0) begin // Se a porta abrir fisicamente
                        timer_en <= 1'b0; // Desliga o timer imediatamente
                        state    <= ST_OPEN;
                    end
                    else if (botao_config) begin
                        timer_en <= 1'b0;
                        setup_on <= 1'b1;
                        state    <= ST_SETUP_MODE;
                    end
                    else if (timer_done) begin // Se os 5 segundos acabarem e a porta continuar fechada
                        timer_en <= 1'b0; // Desliga o timer
                        state    <= ST_CLOSED_LOCKED; // Tranca a porta novamente
                    end
                end

                ST_OPEN_UNLOCKED: begin
                    // 1. Configuração das Saídas (Segurança Mecânica)
                    tranca          <= 1'b0; // Garante pino recolhido para não danificar o batente
                    teclado_en      <= 1'b0; // Teclado inativo para senhas
                    display_en      <= 1'b1; // Display ativo (pode exibir um indicativo visual)
                    bip             <= 1'b0;
                    setup_on        <= 1'b0;
                    //Garante que o timer genérico fique desligado enquanto a porta estiver aberta!
                    timer_en   <= 1'b0;
                    
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
                    // NOVO: Garante timer desligado
                    timer_en   <= 1'b0;

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

                ST_BLOCK_OUTSIDE: begin
                    tranca     <= 1'b1; 
                        teclado_en <= 1'b0; // Ignora o teclado externo
                        display_en <= 1'b0; 
                        bip        <= 1'b0;
                        setup_on   <= 1'b0;

                        // Lógica 1: Destrancamento imediato por dentro
                        if (botao_interno) begin
                            timer_en <= 1'b0; // Desliga o timer caso estivesse rodando
                            state    <= ST_CLOSED_UNLOCKED; 
                        end
                        
                        // Lógica 2: Desativando o bloqueio pelo próprio botão (3 segundos)
                        else if (botao_bloqueio) begin
                            timer_limit <= 13'd3000; // Define alvo: 3000 ciclos (3 segundos)
                            timer_en    <= 1'b1;     // Liga o timer
                            
                            // Fica escutando a resposta do contador
                            if (timer_done) begin
                                timer_en <= 1'b0;             // Desliga o timer
                                state    <= ST_CLOSED_LOCKED; // Volta ao repouso normal (teclado volta a funcionar)
                            end
                        end 
                        
                        // Lógica 3: Repouso dentro do estado
                        else begin
                            timer_en <= 1'b0; // Se não apertou o botão interno nem o de bloqueio, garante timer zerado
                        end
                    end

                // --- MENU 05: CONFIGURAÇÃO DE SENHA USUÁRIO 1 ---
                ST_RESET_TOTAL: begin
                    // 1. Configurações de Inicialização (Modo Seguro)
                    teclado_en <= 1'b0; // Desabilita o teclado durante a checagem de segurança
                    display_en <= 1'b0; 
                    bip        <= 1'b0;
                    setup_on   <= 1'b0;
                    timer_en   <= 1'b0;

                    // 2. Tomada de decisão baseada na Seção 20.3
                    if (sensor_contato == 1'b1) begin
                        // CENÁRIOS 1 e 2: Porta está fechada.
                        // Garante a tranca acionada e vai para o repouso trancado normal.
                        tranca <= 1'b1; 
                        state  <= ST_CLOSED_LOCKED;
                    end 
                    else begin
                        // CENÁRIO 3: Porta está aberta.
                        // Recolhe a tranca para não quebrar o pino e joga a FSM para o ST_OPEN.
                        // Lá no ST_OPEN, quando a porta fechar, ela irá automaticamente para 
                        // ST_CLOSED_UNLOCKED e rodará o timer de travamento, cumprindo o PDF!
                        tranca <= 1'b0; 
                        state  <= ST_OPEN;
                    end
                end

                // --- MENU 06: CONFIGURAÇÃO DE SENHA USUÁRIO 2 ---
                ST_RESET_PARCIAL: begin
                    // 1. Configurações de Inicialização Segura
                    teclado_en <= 1'b0; // Desabilita o teclado durante a checagem
                    display_en <= 1'b0; 
                    bip        <= 1'b0;
                    setup_on   <= 1'b0;
                    timer_en   <= 1'b0; // Garante o timer zerado

                    // 2. Avaliação dos Sensores Físicos (Exigência da Seção 20.3)
                    if (sensor_contato == 1'b1) begin
                        // Porta está fechada: aciona a tranca e vai para o modo operacional trancado
                        tranca <= 1'b1; 
                        state  <= ST_CLOSED_LOCKED;
                    end 
                    else begin
                        // Porta está aberta: recolhe o pino e vai para ST_OPEN aguardar o fechamento
                        tranca <= 1'b0; 
                        state  <= ST_OPEN;
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


