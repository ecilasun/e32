`timescale 1ns / 1ps

`include "devices.vh"

module spidriver(
	input wire spibaseclock,
	input wire cpuclock,
	input wire reset,
	input wire enable,
	output wire busy,
	input wire buswe,
	input wire busre,
	input wire [7:0] din,
	output bit [7:0] dout = 8'd0,
	output wire spi_cs_n,
	output wire spi_mosi,
	input wire spi_miso,
	output wire spi_sck );

// ----------------------------------------------------------------------------
// SPI Master Device
// ----------------------------------------------------------------------------

bit spioutdv = 1'b0;
wire cansend;
bit [7:0] spisenddata;

wire hasvaliddata;
wire [7:0] spiincomingdata;

// Base clock is @100MHz, therefore we're running at 25MHz (2->2x2 due to 'half'->100/4==25)
SPI_Master #(.SPI_MODE(0), .CLKS_PER_HALF_BIT(2)) SPI(
   // Control/Data Signals,
   .i_Rst_L(~reset),
   .i_Clk(spibaseclock),
   
   // TX (MOSI) Signals
   .i_TX_Byte(spisenddata),
   .i_TX_DV(spioutdv),
   .o_TX_Ready(cansend),
   
   // RX (MISO) Signals
   .o_RX_DV(hasvaliddata),
   .o_RX_Byte(spiincomingdata),

   // SPI Interface
   .o_SPI_Clk(spi_sck),
   .i_SPI_MISO(spi_miso),
   .o_SPI_MOSI(spi_mosi) );

assign spi_cs_n = 1'b0; // Keep attached SPI device selected

// ----------------------------------------------------------------------------
// SPI Send
// ----------------------------------------------------------------------------

wire spitxbusy;

wire [7:0] spisenddout;
bit spisendre = 1'b0;
wire spisendfull, spisendempty, spisendvalid;

spififo SPIDataOutFIFO(
	.full(spisendfull),
	.din(din),
	.wr_en(buswe),
	.wr_clk(cpuclock), // Write using cpu clock
	.empty(spisendempty),
	.valid(spisendvalid),
	.dout(spisenddout),
	.rd_en(spisendre),
	.rd_clk(spibaseclock), // Read using SPI base clock
	.rst(reset) );

bit [1:0] spiwritemode = 2'b00;

always @(posedge spibaseclock) begin
	spisendre <= 1'b0;
	spioutdv <= 1'b0;
	unique case(spiwritemode)
		2'b00: begin // IDLE
			if (~spisendempty & cansend) begin
				spisendre <= 1'b1;
				spiwritemode <= 2'b01; // WRITE
			end
		end
		2'b01: begin // WRITE
			if (spisendvalid) begin
				spioutdv <= 1'b1;
				spisenddata <= spisenddout;
				spiwritemode <= 2'b10; // FINALIZE
			end
		end
		2'b10: begin // FINALIZE
			// Need to give SPI one clock to
			// kick 'busy' for any adjacent
			// requests which didn't set busy yet
			spiwritemode <= 2'b00; // IDLE
		end
	endcase
end

// ----------------------------------------------------------------------------
// SPI Receive
// ----------------------------------------------------------------------------


wire spircvfull, spircvvalid;
bit [7:0] spircvdin = 8'h00;
wire [7:0] spircvdout;
bit spircvre = 1'b0, spircvwe = 1'b0;

spififo SPIDataInFIFO(
	.full(spircvfull),
	.din(spircvdin),
	.wr_en(spircvwe),
	.wr_clk(spibaseclock),
	.empty(spircvempty),
	.dout(spircvdout),
	.rd_en(spircvre),
	.valid(spircvvalid),
	.rd_clk(cpuclock),
	.rst(reset) );

// Record all incoming data from SPI
always @(posedge spibaseclock) begin
	spircvwe <= 1'b0;
	// NOTE: Any byte that won't fit into the FIFO will be dropped
	// Make sure to consume them quickly on arrival!
	if (hasvaliddata & (~spisendfull)) begin
		spircvwe <= 1'b1;
		spircvdin <= spiincomingdata;
	end
end

// Pull data from the FIFO whenever a read request is placed
// FIFO is fallthrough so it will signal valid as soon as it
// sees the read enable.
bit readpending = 1'b0;
always @(posedge cpuclock) begin

	spircvre <= 1'b0;

	if (busre) begin
		dout <= 8'hFF;
		spircvre <= (~spircvempty);
		readpending <= (~spircvempty);
	end

	if (spircvvalid) begin
		dout <= spircvdout;
		readpending <= 1'b0;
	end
end

// Bus stall signal
assign busy = enable & ((busre | readpending) | (buswe & spisendfull));

endmodule
