module debounce(input clk, rst, s_in, output logic s_out);
  int cont;
  always @(posedge clk or posedge rst) begin
    if(rst) begin
      cont  = 0;
      s_out = 0;
    end
    else
      if( s_in ) begin
			  cont++;
			  if (cont > 200)
					s_out = 1;
			  else
					s_out = 0;
				end  
      else begin
        cont = 0;
		  s_out = 0;
      end
  end
endmodule

