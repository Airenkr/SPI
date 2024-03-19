// SPI-Top module, CPOL = 0, CPHA = 0;
module SPI
#(
	parameter CLK_FREQUENCY = 100_000_000, // Clock frequency
	parameter SPI_FREQUENCY = 5_000_000, // SPI frequency
	parameter DATA_WIDTH = 16 // Data Width
)
(
	input clk, // Clock
	input rst_n, // Reset, active-low
    input start, // Start button
	(*mark_debug = "true"*) output [DATA_WIDTH - 1:0] data_out_master // Data processed by slave module
);

localparam IDLE = 0; // Idle State
localparam WORK = 1; // Master to Slave data transfer, the counter stops

(*mark_debug = "true"*) reg [DATA_WIDTH - 1:0] data_in_master; // Counter, Master to Slave data
(*mark_debug = "true"*) wire start_en; // Start Enable signal
reg start_reg0, start_reg1; // Start signal pipeline
wire miso; // Master input, Slave out port
wire sclk; // SPI Clock
wire cs_n; // CS_N (valid) signal, active-low
wire mosi; // Master output, Slave input port
wire data_valid; // Slave data valid
reg cstate, nstate; // Current and Next states for FSM

//------------------------------------------------------------------------
// Rising edge detector
always @ (posedge clk, negedge rst_n) begin
	if (!rst_n) begin
		start_reg0 <= 1'b0;
		start_reg1 <= 1'b0;
	end
	else begin
		start_reg0 <= start;
		start_reg1 <= start_reg0;
	end
end

assign start_en = ~start_reg1 & start_reg0; // Data posedge

//------------------------------------------------------------------------
// SPI Master module
SPI_master #(.CLK_FREQUENCY(CLK_FREQUENCY), 
		.SPI_FREQUENCY(SPI_FREQUENCY), 
		.DATA_WIDTH(DATA_WIDTH)) master
	  (.clk(clk),
	   .rst_n(rst_n),
		.data_in(data_in_master),
		.start(start_en),
		.miso(miso),
		.sclk(sclk),
		.cs_n(cs_n),
		.mosi(mosi),
		.data_out(data_out_master));

//------------------------------------------------------------------------
// SPI Slave module	
SPI_slave #(.DATA_WIDTH(DATA_WIDTH)) slave
			  (.clk(clk),
			   .rst_n(rst_n),
			   .sclk(sclk),
			   .cs_n(cs_n),
			   .mosi(mosi),
			   .miso(miso),
			   .data_valid(data_valid)
			  );

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
		IDLE : nstate = start_en ? WORK : IDLE; // If start_en == 1 -> WORK State, Else -> IDLE
		WORK : nstate = data_valid ? IDLE : WORK; // If data_valid == 1 -> IDLE State, Else -> WORK
		default : nstate = IDLE; // Default state - IDLE
	endcase
end

//------------------------------------------------------------------------
// FSM
always @ (posedge clk, negedge rst_n) begin
	if (!rst_n) begin
		data_in_master <= 'd0;
	end
	else begin
		case (nstate)
			IDLE : begin
				data_in_master <= data_in_master + 1'b1; // Start counter
			end
			WORK : begin
				data_in_master <= data_in_master; // Stop counter
			end
			default : begin
				data_in_master <= data_in_master + 1'b1; // Start counter
			end
		endcase
	end
end

endmodule