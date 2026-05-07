module segment7( bcd, seg );
     
	 input [3:0] bcd;
	 output [6:0] seg;
	 reg [6:0] seg;

	 always @(bcd)
	 begin
		  case (bcd) 
				0  : seg = 7'b1000000;
				1  : seg = 7'b1111001;
				2  : seg = 7'b0100100;
				3  : seg = 7'b0110000;
				4  : seg = 7'b0011001;
				5  : seg = 7'b0010010;
				6  : seg = 7'b0000010;
				7  : seg = 7'b1111000;
				8  : seg = 7'b0000000;
				9  : seg = 7'b0011000;
				10 : seg = 7'b0001000;
				11 : seg = 7'b0000011;
				12 : seg = 7'b1111111; //alterado para não mostrar nada, sendo usado para apagar o display
				13 : seg = 7'b0100001;
				14 : seg = 7'b0000110;        
				15 : seg = 7'b0001110;
				default : seg = 7'b1111111; 
		  endcase
	 end 
endmodule

