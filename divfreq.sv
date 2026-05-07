module divfreq(input reset, clock, output logic clk_i);
  int cont;
  always @(posedge clock or posedge reset) begin
    if(reset) begin
      cont  = 0;
      clk_i = 0;
    end
    else
      if( cont <= 25000 )
        cont++;
      else begin
        clk_i = ~clk_i;
        cont = 0;
      end
  end
endmodule


