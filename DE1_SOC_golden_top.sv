// ============================================================================
// Copyright (c) 2013 by Terasic Technologies Inc.
// ============================================================================
//
// Permission:
//
//   Terasic grants permission to use and modify this code for use
//   in synthesis for all Terasic Development Boards and Altera Development 
//   Kits made by Terasic.  Other use of this code, including the selling 
//   ,duplication, or modification of any portion is strictly prohibited.
//
// Disclaimer:
//
//   This VHDL/Verilog or C/C++ source code is intended as a design reference
//   which illustrates how these types of functions can be implemented.
//   It is the user's responsibility to verify their design for
//   consistency and functionality through the use of formal
//   verification methods.  Terasic provides no warranty regarding the use 
//   or functionality of this code.
//
// ============================================================================
//           
//  Terasic Technologies Inc
//  9F., No.176, Sec.2, Gongdao 5th Rd, East Dist, Hsinchu City, 30070. Taiwan
//  
//  
//                     web: http://www.terasic.com/  
//                     email: support@terasic.com
//
// ============================================================================
//Date:  Thu Jul 11 11:26:45 2013
// ============================================================================

`define ENABLE_ADC
`define ENABLE_AUD
`define ENABLE_CLOCK2
`define ENABLE_CLOCK3
`define ENABLE_CLOCK4
`define ENABLE_CLOCK
`define ENABLE_DRAM
`define ENABLE_FAN
`define ENABLE_FPGA
`define ENABLE_GPIO
`define ENABLE_HEX
//`define ENABLE_HPS
`define ENABLE_IRDA
`define ENABLE_KEY
`define ENABLE_LEDR
`define ENABLE_PS2
`define ENABLE_SW
`define ENABLE_TD
`define ENABLE_VGA

module DE1_SOC_golden_top(

      /* Enables ADC - 3.3V */
	`ifdef ENABLE_ADC

      output             ADC_CONVST,
      output             ADC_DIN,
      input              ADC_DOUT,
      output             ADC_SCLK,

	`endif

       /* Enables AUD - 3.3V */
	`ifdef ENABLE_AUD

      input              AUD_ADCDAT,
      inout              AUD_ADCLRCK,
      inout              AUD_BCLK,
      output             AUD_DACDAT,
      inout              AUD_DACLRCK,
      output             AUD_XCK,

	`endif

      /* Enables CLOCK2  */
	`ifdef ENABLE_CLOCK2
      input              CLOCK2_50,
	`endif

      /* Enables CLOCK3 */
	`ifdef ENABLE_CLOCK3
      input              CLOCK3_50,
	`endif

      /* Enables CLOCK4 */
	`ifdef ENABLE_CLOCK4
      input              CLOCK4_50,
	`endif

      /* Enables CLOCK */
	`ifdef ENABLE_CLOCK
      input              CLOCK_50,
	`endif

       /* Enables DRAM - 3.3V */
	`ifdef ENABLE_DRAM
      output      [12:0] DRAM_ADDR,
      output      [1:0]  DRAM_BA,
      output             DRAM_CAS_N,
      output             DRAM_CKE,
      output             DRAM_CLK,
      output             DRAM_CS_N,
      inout       [15:0] DRAM_DQ,
      output             DRAM_LDQM,
      output             DRAM_RAS_N,
      output             DRAM_UDQM,
      output             DRAM_WE_N,
	`endif

      /* Enables FAN - 3.3V */
	`ifdef ENABLE_FAN
      output             FAN_CTRL,
	`endif

      /* Enables FPGA - 3.3V */
	`ifdef ENABLE_FPGA
      output             FPGA_I2C_SCLK,
      inout              FPGA_I2C_SDAT,
	`endif

      /* Enables GPIO - 3.3V */
	`ifdef ENABLE_GPIO
      inout     [35:0]         GPIO_0,
      inout     [35:0]         GPIO_1,
	`endif
 

      /* Enables HEX - 3.3V */
	`ifdef ENABLE_HEX
      output      [6:0]  HEX0,
      output      [6:0]  HEX1,
      output      [6:0]  HEX2,
      output      [6:0]  HEX3,
      output      [6:0]  HEX4,
      output      [6:0]  HEX5,
	`endif
	
	/* Enables HPS */
	`ifdef ENABLE_HPS
      inout              HPS_CONV_USB_N,
      output      [14:0] HPS_DDR3_ADDR,
      output      [2:0]  HPS_DDR3_BA,
      output             HPS_DDR3_CAS_N,
      output             HPS_DDR3_CKE,
      output             HPS_DDR3_CK_N, //1.5V
      output             HPS_DDR3_CK_P, //1.5V
      output             HPS_DDR3_CS_N,
      output      [3:0]  HPS_DDR3_DM,
      inout       [31:0] HPS_DDR3_DQ,
      inout       [3:0]  HPS_DDR3_DQS_N,
      inout       [3:0]  HPS_DDR3_DQS_P,
      output             HPS_DDR3_ODT,
      output             HPS_DDR3_RAS_N,
      output             HPS_DDR3_RESET_N,
      input              HPS_DDR3_RZQ,
      output             HPS_DDR3_WE_N,
      output             HPS_ENET_GTX_CLK,
      inout              HPS_ENET_INT_N,
      output             HPS_ENET_MDC,
      inout              HPS_ENET_MDIO,
      input              HPS_ENET_RX_CLK,
      input       [3:0]  HPS_ENET_RX_DATA,
      input              HPS_ENET_RX_DV,
      output      [3:0]  HPS_ENET_TX_DATA,
      output             HPS_ENET_TX_EN,
      inout       [3:0]  HPS_FLASH_DATA,
      output             HPS_FLASH_DCLK,
      output             HPS_FLASH_NCSO,
      inout              HPS_GSENSOR_INT,
      inout              HPS_I2C1_SCLK,
      inout              HPS_I2C1_SDAT,
      inout              HPS_I2C2_SCLK,
      inout              HPS_I2C2_SDAT,
      inout              HPS_I2C_CONTROL,
      inout              HPS_KEY,
      inout              HPS_LED,
      inout              HPS_LTC_GPIO,
      output             HPS_SD_CLK,
      inout              HPS_SD_CMD,
      inout       [3:0]  HPS_SD_DATA,
      output             HPS_SPIM_CLK,
      input              HPS_SPIM_MISO,
      output             HPS_SPIM_MOSI,
      inout              HPS_SPIM_SS,
      input              HPS_UART_RX,
      output             HPS_UART_TX,
      input              HPS_USB_CLKOUT,
      inout       [7:0]  HPS_USB_DATA,
      input              HPS_USB_DIR,
      input              HPS_USB_NXT,
      output             HPS_USB_STP,
`endif 

      /* Enables IRDA - 3.3V */
	`ifdef ENABLE_IRDA
      input              IRDA_RXD,
      output             IRDA_TXD,
	`endif

      /* Enables KEY - 3.3V */
	`ifdef ENABLE_KEY
      input       [3:0]  KEY,
	`endif

      /* Enables LEDR - 3.3V */
	`ifdef ENABLE_LEDR
      output      [9:0]  LEDR,
	`endif

      /* Enables PS2 - 3.3V */
	`ifdef ENABLE_PS2
      inout              PS2_CLK,
      inout              PS2_CLK2,
      inout              PS2_DAT,
      inout              PS2_DAT2,
	`endif

      /* Enables SW - 3.3V */
	`ifdef ENABLE_SW
      input       [9:0]  SW,
	`endif

      /* Enables TD - 3.3V */
	`ifdef ENABLE_TD
      input             TD_CLK27,
      input      [7:0]  TD_DATA,
      input             TD_HS,
      output            TD_RESET_N,
      input             TD_VS,
	`endif

      /* Enables VGA - 3.3V */
	`ifdef ENABLE_VGA
      output      [7:0]  VGA_B,
      output             VGA_BLANK_N,
      output             VGA_CLK,
      output      [7:0]  VGA_G,
      output             VGA_HS,
      output      [7:0]  VGA_R,
      output             VGA_SYNC_N,
      output             VGA_VS
	`endif
);

import projeto_types::*; // Importa os tipos do pacote

//=======================================================
//  REG/WIRE declarations
//=======================================================

wire CLK_1K, SW_0, SW_1, SW_2, SW_3, SW_4, SW_5, SW_6, SW_7, SW_8, SW_9;

setupPac_t		      SETUP_PAC;
senhaPac_t              DIGITOS_VALUE;
logic 			DIGITOS_VALID;
bcdPac_t                BUS_DISPLAY;

//=======================================================
//  Structural coding
//=======================================================

divfreq  my_div(
      .reset(!KEY[0]),
      .clock(CLOCK_50),
      .clk_i(CLK_1K)
);
	
	
setup my_setup (
      .clk(CLK_1K),
      .rst(!KEY[1]),
      .setup_on(SW_0),
      .digitos_value(DIGITOS_VALUE),
      .digitos_valid(DIGITOS_VALID),
      .display_en( LEDR[2] ),
      .bcd_pac(BUS_DISPLAY),
      .data_setup_new(SETUP_PAC),
      .data_setup_ok(LEDR[9])
);


decodificador_de_teclado my_teclado (
      .clk(CLK_1K),
      .rst(!KEY[1]),
      .enable(KEY[2]),
      .col_matriz({GPIO_0[16],GPIO_0[14],GPIO_0[12],GPIO_0[10]}),
      .lin_matriz({GPIO_0[24],GPIO_0[22],GPIO_0[20],GPIO_0[18]}),
      .digitos_value(DIGITOS_VALUE),
      .digitos_valid(DIGITOS_VALID)
);
	
assign LEDR[0] = SW_0;	
	
//=======================================================
// LÓGICA DE MULTIPLEXAÇÃO 
//=======================================================
logic [4:0] bcd_mux0, bcd_mux1, bcd_mux2, bcd_mux3, bcd_mux4, bcd_mux5;

always_comb begin
    if (SW_0) begin 
        // Injeta 12 ( que no modulo sement7 está como tudo em 1, limpando os sementos) para os 4 primeiros dígitos, indicando que o display está em modo de configuração
        bcd_mux0 = 4'd12; 
        bcd_mux1 = 4'd12;
        bcd_mux2 = 4'd12;
        bcd_mux3 = 4'd12;
        
        // Garante a conversão correta estendendo para 5 bits
        bcd_mux4 = {1'b0, BUS_DISPLAY.BCD4};
        bcd_mux5 = {1'b0, BUS_DISPLAY.BCD5};
    end
    else begin       
        bcd_mux0 = {1'b0, DIGITOS_VALUE.digits[0]};
        bcd_mux1 = {1'b0, DIGITOS_VALUE.digits[1]};
        bcd_mux2 = {1'b0, DIGITOS_VALUE.digits[2]};
        bcd_mux3 = {1'b0, DIGITOS_VALUE.digits[3]};
        bcd_mux4 = {1'b0, DIGITOS_VALUE.digits[4]};
        bcd_mux5 = {1'b0, DIGITOS_VALUE.digits[5]};
    end
end

//=======================================================
// INSTANCIAÇÃO ÚNICA DOS DECODIFICADORES DE 7 SEGMENTOS
//=======================================================
segment7 CONV_0(.bcd(bcd_mux0), .seg(HEX0));
segment7 CONV_1(.bcd(bcd_mux1), .seg(HEX1));
segment7 CONV_2(.bcd(bcd_mux2), .seg(HEX2));
segment7 CONV_3(.bcd(bcd_mux3), .seg(HEX3));
segment7 CONV_4(.bcd(bcd_mux4), .seg(HEX4));
segment7 CONV_5(.bcd(bcd_mux5), .seg(HEX5));

debounce my_sw0(.clock(CLK_1K), .reset(!KEY[1]), .s_in(SW[0]), .s_out(SW_0));
debounce my_sw1(.clock(CLK_1K), .reset(!KEY[1]), .s_in(SW[1]), .s_out(SW_1));
debounce my_sw2(.clock(CLK_1K), .reset(!KEY[1]), .s_in(SW[2]), .s_out(SW_2));
debounce my_sw3(.clock(CLK_1K), .reset(!KEY[1]), .s_in(SW[3]), .s_out(SW_3));
debounce my_sw4(.clock(CLK_1K), .reset(!KEY[1]), .s_in(SW[4]), .s_out(SW_4));
debounce my_sw5(.clock(CLK_1K), .reset(!KEY[1]), .s_in(SW[5]), .s_out(SW_5));
debounce my_sw6(.clock(CLK_1K), .reset(!KEY[1]), .s_in(SW[6]), .s_out(SW_6));
debounce my_sw7(.clock(CLK_1K), .reset(!KEY[1]), .s_in(SW[7]), .s_out(SW_7));
debounce my_sw8(.clock(CLK_1K), .reset(!KEY[1]), .s_in(SW[8]), .s_out(SW_8));
debounce my_sw9(.clock(CLK_1K), .reset(!KEY[1]), .s_in(SW[9]), .s_out(SW_9));

endmodule