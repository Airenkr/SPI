// SPI Slave module
module SPI_slave
#(
	parameter DATA_WIDTH = 16 // Data Width
)
(
	input clk, // Clock
	input rst_n, // Reset, active-low
	(*mark_debug = "true"*) input sclk, // SPI Clock
	(*mark_debug = "true"*) input cs_n, // CS_N (valid) signal, active-low
	(*mark_debug = "true"*) input mosi, // Master output, Slave input port
	(*mark_debug = "true"*) output miso, // Master input, Slave out port
	output data_valid // Slave data valid
);

localparam SAMPL_WIDTH = $clog2(DATA_WIDTH); // sampl_num Width

reg [DATA_WIDTH - 1:0] data_reg; // Slave output data
reg [SAMPL_WIDTH:0] sampl_num; // Sample counter
reg sclk_a, sclk_b; // SPI Clock pipeline
wire sclk_posedge, sclk_negedge; // SPI Clock posedge and negedge
reg cs_n_a, cs_n_b; // CS_N pipeline
(*mark_debug = "true"*) wire cs_n_posedge; // CS_N Posedge
(*mark_debug = "true"*) wire cs_n_negedge; // CS_N Negedge
wire shift_en; // Shift data Enable
wire sampl_en; // Sample data Enable
reg [1:0] cs_cnt; // CS_N Counter
reg [DATA_WIDTH - 1:0] data_out; // Slave input data
(*mark_debug = "true"*) reg [DATA_WIDTH - 1:0] data; // Inverted input data

reg cs_n_reg0, cs_n_reg1; // CS_N pipeline
reg sclk_reg0, sclk_reg1; // SPI Clock pipeline
reg mosi_reg0, mosi_reg1; // MOSI pipeline

//------------------------------------------------------------------------
// Input ports Pipelines
always @ (posedge clk, negedge rst_n) begin
	if (!rst_n) begin
		cs_n_reg0 <= 0;
		cs_n_reg1 <= 0;
		sclk_reg0 <= 0;
		sclk_reg1 <= 0;
		mosi_reg0 <= 0;
		mosi_reg1 <= 0;
	end
	else begin
		cs_n_reg0 <= cs_n;
		cs_n_reg1 <= cs_n_reg0;
		sclk_reg0 <= sclk;
		sclk_reg1 <= sclk_reg0;
		mosi_reg0 <= mosi;
		mosi_reg1 <= mosi_reg0;
	end
end

//------------------------------------------------------------------------
// Rising and Falling SPI Clock Edges detector
//CPOL == 0
always @ (posedge clk, negedge rst_n) begin
	if (!rst_n) begin
		sclk_a <= 0;
		sclk_b <= 0;
	end
	else if (!cs_n_reg1) begin
		sclk_a <= sclk_reg1;
		sclk_b <= sclk_a;
	end
end

assign sclk_posedge = ~sclk_b & sclk_a;
assign sclk_negedge = ~sclk_a & sclk_b;

//------------------------------------------------------------------------
// Rising and Falling CS_N Edges detector
always @ (posedge clk, negedge rst_n) begin
	if (!rst_n) begin
		cs_n_a <= 1'b0;
		cs_n_b <= 1'b0;
	end
	else begin
		cs_n_a <= cs_n_reg1;
		cs_n_b <= cs_n_a;
	end
end

assign cs_n_negedge = ~cs_n_a & cs_n_b;
assign cs_n_posedge = ~cs_n_a & cs_n_reg1;

//------------------------------------------------------------------------
// Enable signals for CPHA = 0
assign sampl_en = sclk_posedge;
assign shift_en = sclk_negedge;

//------------------------------------------------------------------------
// CS_N Counter
always @ (posedge clk, negedge rst_n) begin
	if (!rst_n) begin
		cs_cnt <= 2'd0;
	end
	else if (cs_n_negedge) begin
		cs_cnt <= cs_cnt + 1'd1;
	end
	else if (cs_cnt == 2'd2) begin
		cs_cnt <= 2'd0;
	end
	else begin
		cs_cnt <= cs_cnt;
	end
end

//------------------------------------------------------------------------
// Proccessing data received from the master device
always @ (posedge clk, negedge rst_n) begin
	if (!rst_n) begin
		data <= 'd0;
	end
	else if (cs_cnt == 2'd1 && data_valid) begin
		data <= ~data_out;
	end
	else begin
		data <= data;
	end
end

//------------------------------------------------------------------------
// Generation MISO
always @ (posedge clk, negedge rst_n) begin
	if (!rst_n) begin
		data_reg <= 'd0;
	end
	else if (cs_n_negedge) begin
		data_reg <= data; // Inverted data enters the register on a CS_N falling edge
	end
	else if (!cs_n_reg1 & shift_en) begin
		data_reg <= {data_reg[DATA_WIDTH - 2:0], 1'b0}; // Data is shifted when CS_N == 0 and shift_en == 1
	end
	else begin
		data_reg <= data_reg;
	end
end

assign miso = !cs_n_reg1 ? data_reg[DATA_WIDTH - 1] : 1'b0; // MISO signal

//------------------------------------------------------------------------
// Receiving data from Master
always @ (posedge clk, negedge rst_n) begin
	if (!rst_n) begin
		data_out <= 'd0;
	end
	else if (!cs_n_reg1 & sampl_en) begin
		data_out <= {data_out[DATA_WIDTH - 2:0], mosi_reg1}; // Data received when CS_N == 0 and sampl_en == 1
	end
	else begin
		data_out <= data_out;
	end
end

//------------------------------------------------------------------------
// Sample counter
always @ (posedge clk, negedge rst_n) begin 
	if (!rst_n) begin
		sampl_num <= 'd0;
	end
	else if (cs_n_reg1) begin
		sampl_num <= 'd0; // sampl_num == 0 when CS_N == 1
	end
	else if (!cs_n_reg1 & sampl_en) begin
		if (sampl_num == DATA_WIDTH) begin
			sampl_num <= 'd1;
		end
		else begin
			sampl_num <= sampl_num + 1'b1;
		end
	end
	else begin
		sampl_num <= sampl_num;
	end
end

//------------------------------------------------------------------------
// Data Valid signal
assign data_valid = (sampl_num == DATA_WIDTH && cs_n_posedge);

endmodule