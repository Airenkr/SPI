module testbench(); 

parameter CLK_FREQUENCY = 100_000_000;
parameter SPI_FREQUENCY = 5_000_000;
parameter DATA_WIDTH = 16;

logic clk;
logic rst_n;
logic start;
logic [DATA_WIDTH - 1:0] data_out_master;

SPI #(.CLK_FREQUENCY(CLK_FREQUENCY),
        .SPI_FREQUENCY(SPI_FREQUENCY),
        .DATA_WIDTH(DATA_WIDTH)) spi
     (.clk(clk),
      .rst_n(rst_n),
      .start(start),
      .data_out_master(data_out_master));
      
initial begin
	clk = 0;
	forever clk = #(5) ~clk;
end

initial begin 
    rst_n = 0;
    start = 0;
    repeat(5) @(posedge clk);
    rst_n = 1;
    repeat(5) @(posedge clk);
    start = 1;
//    repeat(5) @(posedge clk);
//    start = 0;
//    repeat(1200) @(posedge clk);
//    start = 1;
end

endmodule
