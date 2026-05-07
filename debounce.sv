module debounce(input clock, reset, s_in, output logic s_out);
  int cont;
  always @(posedge clock or posedge reset) begin
    if(reset) begin
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

