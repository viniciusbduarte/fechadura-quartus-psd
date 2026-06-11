`include "projeto_types.sv"
module display (

    input 		logic 		clk, 
    input 		logic 		rst,
    input 		logic 		enable_o, enable_s,
    input 		bcdPac_t 	bcd_packet_operacional, bcd_packet_setup,
    output 		logic [6:0] 	HEX0, HEX1,HEX2, HEX3, HEX4, HEX5
);
    import projeto_types::*;
    bcdPac_t current_bcd;

    always_comb begin
        if (enable_o && enable_s) begin
            current_bcd = '{default:4'd14}; // Show 'E' for error
        end else if (enable_s) begin
            current_bcd = bcd_packet_setup;
        end else if (enable_o) begin
            current_bcd = bcd_packet_operacional;
        end else begin
            current_bcd = '{default:4'd12}; // Clear displays
        end
    end

    segment7 u0 (
        .bcd(current_bcd.BCD0),
        .seg(HEX0)
    );

    segment7 u1 (
        .bcd(current_bcd.BCD1),
        .seg(HEX1)
    );

    segment7 u2 (
        .bcd(current_bcd.BCD2),
        .seg(HEX2)
    );

    segment7 u3 (
        .bcd(current_bcd.BCD3),
        .seg(HEX3)
    );

    segment7 u4 (
        .bcd(current_bcd.BCD4),
        .seg(HEX4)
    );

    segment7 u5 (
        .bcd(current_bcd.BCD5),
        .seg(HEX5)
    );

endmodule