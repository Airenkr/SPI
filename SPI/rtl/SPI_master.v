// SPI Master module
module SPI_master
#(
	parameter CLK_FREQUENCY = 100_000_000, // Clock frequency
	parameter SPI_FREQUENCY = 5_000_000, // SPI frequency
	parameter DATA_WIDTH = 16 // Data Width
)
(
	input clk, // Clock
	input rst_n, // Reset, active-low
	input [DATA_WIDTH - 1:0] data_in, // Master to Slave data
	input start, // Start signal
	input miso, // Master input, Slave output
	output reg sclk, // SPI Clock
	output reg cs_n, // CS_N (valid) signal, active-low
	output mosi, // Master output, Slave input
	output reg [DATA_WIDTH - 1:0] data_out // Slave to Master data
);

localparam FREQUENCY_CNT = CLK_FREQUENCY/SPI_FREQUENCY - 1; // Clock Divider 
localparam SHIFT_WIDTH = $clog2(DATA_WIDTH) + 1; // Shift Counter Width
localparam CNT_WIDTH = $clog2(FREQUENCY_CNT); // Clock Divider Width

localparam IDLE = 0; // Idle State
localparam LOAD = 1; // Load data State
localparam SHIFT = 2; // Shift State
localparam DONE = 3; // Done State

reg [2:0] cstate, nstate; // Current and Next states for FSM
reg clk_cnt_en; // Clock counter Enable
reg sclk_a, sclk_b; // SPI Clock pipeline
wire sclk_posedge, sclk_negedge; // SPI Clock posedge and negedge
wire shift_en; // Shift Enable
wire sampl_en; // Sample Enable
reg [CNT_WIDTH - 1:0] clk_cnt; // Clock Counter
reg [SHIFT_WIDTH - 1:0] shift_cnt; // Shift Counter
reg [DATA_WIDTH - 1:0] data_reg; // Master to Slave Data
reg [DATA_WIDTH - 1:0] data_out_reg; // Slave to Master Data
reg start_reg; // Start Register
reg [1:0] load_cnt; // Load State Counter

//------------------------------------------------------------------------
// Clock Divider
always @ (posedge clk, negedge rst_n) begin
	if (!rst_n)
		clk_cnt = 1'b0;
	else if (clk_cnt_en)
		if (clk_cnt == FREQUENCY_CNT)
			clk_cnt <= 1'b0;
		else
			clk_cnt <= clk_cnt + 1'b1;
	else
		clk_cnt <= 1'b0;
end

//------------------------------------------------------------------------
// SPI Clock Generation, CPOL == 0
always @ (posedge clk, negedge rst_n) begin
	if (!rst_n)
		sclk <= 0;
	else if (clk_cnt_en)
		if (clk_cnt == FREQUENCY_CNT)
			sclk <= ~sclk;
		else
			sclk <= sclk;
	else
		sclk <= 0;
end

//------------------------------------------------------------------------
// Rising and Falling SPI Clock Edges detector, CPOL == 0
always @ (posedge clk, negedge rst_n) begin
	if (!rst_n) begin
		sclk_a <= 0;
		sclk_b <= 0;
	end
	else if (clk_cnt_en) begin
		sclk_a <= sclk;
		sclk_b <= sclk_a;
	end
end

assign sclk_posedge = ~sclk_b & sclk_a;
assign sclk_negedge = ~sclk_a & sclk_b;

//------------------------------------------------------------------------
// Enable signals for CPHA = 0
assign sampl_en = sclk_posedge;
assign shift_en = sclk_negedge;

//------------------------------------------------------------------------
// Start for Two packages
always @ (posedge clk, negedge rst_n) begin
	if (!rst_n) begin
		start_reg <= 0;
	end
	else if (load_cnt == 2) begin
	   start_reg <= 0; // If second package is loaded, start_reg == 0
	end
	else if (start) begin
		start_reg <= 1; // If start == 1 -> start_reg = 1
	end
	else begin
	   start_reg <= start_reg;
	end
end

//------------------------------------------------------------------------
// Switching to a new state FSM
always @ (posedge clk, negedge rst_n) begin
	if (!rst_n) begin
		cstate <= IDLE;
	end
	else begin
		cstate <= nstate;
	end
end

//------------------------------------------------------------------------
// FSM Logic	
always @ (*) begin
	nstate = cstate;
	case (cstate)
		IDLE : nstate = (start_reg ? LOAD : IDLE);
		LOAD : nstate = SHIFT;
		SHIFT : nstate = (shift_cnt == DATA_WIDTH) ? DONE : SHIFT;
		DONE : nstate = IDLE;
		default : nstate = IDLE;
	endcase
end

//------------------------------------------------------------------------
// FSM
always @ (posedge clk, negedge rst_n) begin
	if (!rst_n) begin
		clk_cnt_en <= 1'b0;
		data_reg <= 'd0;
		cs_n <= 1'b1;
		shift_cnt <= 'd0;
		load_cnt <= 'd0;
	end
	else begin
		case (nstate)
			IDLE : begin
				clk_cnt_en <= 1'b0;
				data_reg <= 'd0;
				cs_n <= 1'b1; // CS_N to 1
				shift_cnt <= 'd0;
				if (load_cnt == 'd2) begin
				    load_cnt <= 0; // If Two packages -> load_cnt == 0
				end
				else begin
				    load_cnt <= load_cnt;
				end
			end
			LOAD : begin
				clk_cnt_en <= 1'b1; // Clock Divider Enable
				data_reg <= data_in; // Load data to data_reg
				cs_n <= 1'b0; // CS_N to 0
				shift_cnt <= 'd0;
				load_cnt <= load_cnt + 1'b1; // load_cnt + 1
			end
			SHIFT : begin
				if (shift_en) begin // If Shift Enable
					shift_cnt <= shift_cnt + 1'b1;
					data_reg <= {data_reg[DATA_WIDTH - 2:0], 1'b0}; // Shift Register
				end
				else begin
					shift_cnt <= shift_cnt;
					data_reg <= data_reg;
				end
				clk_cnt_en <= 1'b1; // Clock Divider Enable
				cs_n <= 1'b0; // CS_N to 0
				load_cnt <= load_cnt;
			end
			DONE : begin
				clk_cnt_en <= 1'b0; // Clock Divider Disable
				data_reg <= 'd0;
				cs_n <= 1'b1; // CS_N to 1
				load_cnt <= load_cnt;
			end
			default : begin // Default State == IDLE State
				clk_cnt_en <= 1'b0;
				data_reg <= 'd0;
				cs_n <= 1'b1; // CS_N to 1
				shift_cnt <= 'd0;
				if (load_cnt == 'd2) begin
				    load_cnt <= 0; // If Two packages -> load_cnt == 0
				end
				else begin
				    load_cnt <= load_cnt;
				end
			end
		endcase
	end
end

//------------------------------------------------------------------------
// MOSI Signal
assign mosi = data_reg[DATA_WIDTH - 1];

//------------------------------------------------------------------------
// Receiving data from Slave
always @ (posedge clk, negedge rst_n) begin
	if (!rst_n) begin
		data_out_reg <= 'd0;
	end
	else if (sampl_en) begin // If Sample Enable
		data_out_reg <= {data_out_reg[DATA_WIDTH - 1:0], miso}; // Shift Register
	end
	else begin
		data_out_reg <= data_out_reg;
	end
end

//------------------------------------------------------------------------
// Slave to Master data
always @ (posedge clk, negedge rst_n) begin
	if (!rst_n) begin
		data_out <= 'd0;
	end
	else if (nstate == DONE) begin
		data_out <= data_out_reg[DATA_WIDTH - 1:0]; // Data to out
	end
	else begin
		data_out <= data_out;
	end
end

endmodule