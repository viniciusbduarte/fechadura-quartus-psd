import projeto_types::*;

module fechadura (
      input 	logic 		clk, 
      input 	logic  		rst,
      input		logic  		sensor_contato,
      input		logic  		botao_interno,
      input 	logic  		botao_bloqueio,
      input 	logic  		botao_config,
      input 	logic [3:0] col_matriz,
      output 	logic [3:0] lin_matriz,
      output 	logic 		tranca,
      output 	logic 		bip,
      output 	logic [6:0] HEX0, 
      output 	logic [6:0] HEX1,
      output 	logic [6:0] HEX2, 
      output 	logic [6:0] HEX3, 
      output 	logic [6:0] HEX4, 
      output 	logic [6:0] HEX5
);

//=======================================================
//  Sinais Internos
//=======================================================
logic clk_1khz;

bcdPac_t bcd_pac_setup, bcd_pac_op;
digitosPac_t digitos_value;
setupPac_t data_setup_new;

logic setup_on, digitos_valid, teclado_en, data_setup_ok, enable_display_op, enable_display_setup;

//=======================================================
//  Codificação Estrutural
//=======================================================

// Divisor de frequência para gerar o clock de 1KHz para o sistema
divfreq div (
    .reset(rst),
    .clock(clk),
    .clk_i(clk_1khz)
);

// Decodificador do teclado matricial
decodificador_de_teclado my_teclado (
	.clk(clk_1khz),
	.rst(rst),
	.enable(teclado_en),
	.col_matriz(col_matriz),
	.lin_matriz(lin_matriz),
	.digitos_value(digitos_value),
	.digitos_valid(digitos_valid)
);

// Módulo de controle do Modo Setup
setup my_setup (
  .clk(clk_1khz),
  .rst(rst),
  .setup_on(setup_on),
  .digitos_value(digitos_value),
  .digitos_valid(digitos_valid),
  .display_en(enable_display_setup),
  .bcd_pac(bcd_pac_setup),       
  .data_setup_new(data_setup_new),
  .data_setup_ok(data_setup_ok)  
);

// Módulo de controle do Modo Operacional
operacional my_operacional (
  .clk(clk_1khz),
  .rst(rst),
  .sensor_contato(sensor_contato),
  .botao_interno(botao_interno),
  .botao_bloqueio(botao_bloqueio),
  .botao_config(botao_config),
  .data_setup_new(data_setup_new),
  .data_setup_ok(data_setup_ok),
  .digitos_value(digitos_value),
  .digitos_valid(digitos_valid),
  .bcd_pac(bcd_pac_op),
  .teclado_en(teclado_en),
  .display_en(enable_display_op),
  .setup_on(setup_on),
  .tranca(tranca),
  .bip(bip)
);

// Módulo de controle dos displays de 7 segmentos
display my_display (
    .clk(clk_1khz), 
    .rst(rst),
    .enable_o(enable_display_op), 
    .enable_s(enable_display_setup),
    .bcd_in_op(bcd_pac_op), 
    .bcd_in_setup(bcd_pac_setup),
    .HEX0(HEX0), .HEX1(HEX1), .HEX2(HEX2), .HEX3(HEX3), .HEX4(HEX4), .HEX5(HEX5)
);

endmodule