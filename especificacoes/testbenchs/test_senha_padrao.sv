`timescale 1ms/1us

module tb_fluxo_confirmacao;

  // ======================================================
  // SINAIS
  // ======================================================

  logic clk;
  logic rst;

  logic sensor_contato;
  logic botao_interno;
  logic botao_bloqueio;
  logic botao_config;

  logic tranca;
  logic bip;
  logic setup_on;

  logic [3:0] col_matriz;
  logic [3:0] lin_matriz;

  digitosPac_t digitos_teclado;
  logic        digitos_valid;

  logic        teclado_en;

  logic        display_en_setup;
  logic        display_en_op;

  bcdPac_t     bcd_pac_setup;
  bcdPac_t     bcd_pac_op;

  setupPac_t   data_setup_new;
  logic        data_setup_ok;

  // ======================================================
  // DUTs
  // ======================================================

  decodificador_de_teclado u_teclado (
      .clk(clk),
      .rst(rst),
      .enable(teclado_en),

      .col_matriz(col_matriz),
      .lin_matriz(lin_matriz),

      .digitos_value(digitos_teclado),
      .digitos_valid(digitos_valid)
  );

  setup u_setup (
      .clk(clk),
      .rst(rst),
      .setup_on(setup_on),

      .digitos_value(digitos_teclado),
      .digitos_valid(digitos_valid),

      .display_en(display_en_setup),
      .bcd_pac(bcd_pac_setup),

      .data_setup_new(data_setup_new),
      .data_setup_ok(data_setup_ok)
  );

  operacional u_operacional (
      .clk(clk),
      .rst(rst),

      .sensor_contato(sensor_contato),
      .botao_interno(botao_interno),
      .botao_bloqueio(botao_bloqueio),
      .botao_config(botao_config),

      .data_setup_new(data_setup_new),
      .data_setup_ok(data_setup_ok),

      .digitos_value(digitos_teclado),
      .digitos_valid(digitos_valid),

      .bcd_pac(bcd_pac_op),

      .teclado_en(teclado_en),
      .display_en(display_en_op),
      .setup_on(setup_on),

      .tranca(tranca),
      .bip(bip)
  );

  // ======================================================
  // CLOCK 1 kHz
  // ======================================================

  always #0.5 clk = ~clk;

  // ======================================================
  // TASK DE PRESSIONAMENTO
  // ======================================================

  task automatic pressionar_tecla(
      input int linha,
      input int coluna,
      input int hold_ms = 150
  );

      logic [3:0] col_code;
      logic [3:0] lin_code;

      case (coluna)
          0: col_code = 4'b0111;
          1: col_code = 4'b1011;
          2: col_code = 4'b1101;
          default: col_code = 4'b1111;
      endcase

      case (linha)
          0: lin_code = 4'b0111;
          1: lin_code = 4'b1011;
          2: lin_code = 4'b1101;
          3: lin_code = 4'b1110;
          default: lin_code = 4'b1111;
      endcase

      wait (lin_matriz === lin_code);

      #0.1;

      col_matriz = col_code;

      #(hold_ms);

      col_matriz = 4'b1111;

      #50;

  endtask

  // ======================================================
  // TESTE PRINCIPAL
  // ======================================================

  initial begin

    $dumpfile("teste.vcd");
      $dumpvars(0, tb_fluxo_confirmacao);

      clk = 0;
      rst = 1;

      sensor_contato = 0;
      botao_interno  = 0;
      botao_bloqueio = 0;
      botao_config   = 0;

      col_matriz = 4'b1111;

      #10;
      rst = 0;

      #50;

      $display("\n=================================");
      $display("TESTE DE SENHA PADRAO 1234");
      $display("=================================\n");

      // 1
      pressionar_tecla(0,0);

      // 2
      pressionar_tecla(0,1);

      // 3
      pressionar_tecla(0,2);

      // 4
      pressionar_tecla(1,0);

      // *
      pressionar_tecla(3,0);

      #200;

      if (tranca == 1'b0)
          $display("[%0t] OK -> Porta destrancada.", $time);
      else
          $display("[%0t] ERRO -> Porta continua trancada.", $time);

      $display("\nAguardando auto-trancamento...\n");

      #5500;

      if (tranca == 1'b1)
          $display("[%0t] OK -> Porta trancou automaticamente.", $time);
      else
          $display("[%0t] ERRO -> Porta permaneceu destrancada.", $time);

      #100;

      $finish;

  end

  // ======================================================
  // MONITORES
  // ======================================================

  always @(posedge digitos_valid)
  begin
      $display("[%0t ms] DIGITOS_VALID", $time);

      $write("Buffer = ");

      for (int i = 19; i >= 0; i--)
          $write("%h", digitos_teclado.digits[i]);

      $display("");
    
    
      for(int i=11;i>=0;i--)
          $write("%h", u_operacional.config_atual.senha_master.digits[i]);

      $display("");
  end

  always @(tranca)
      $display("[%0t ms] TRANCA = %b", $time, tranca);

  always @(bip)
      $display("[%0t ms] BIP = %b", $time, bip);


  
endmodule