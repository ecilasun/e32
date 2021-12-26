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
	output wire spircvempty,
	output wire spi_cs_n,
	output wire spi_mosi,
	input wire spi_miso,
	output wire spi_sck );

// ----------------------------------------------------------------------------
// SPI master device
// ----------------------------------------------------------------------------

wire sddataoutready;
bit [7:0] sddataout = 8'h00;
bit sddatawe = 1'b0;

wire [7:0] sddatain;
wire sddatainready;

SPI_MASTER SPIMaster (
	.CLK(spibaseclock),
	.RST(reset),
	// SPI Master
	.SCLK(spi_sck),
	.CS_N(spi_cs_n),
	.MOSI(spi_mosi),
	.MISO(spi_miso),
	// Output from BUS
	.DIN_LAST(1'b0),
	.DIN_RDY(sddataoutready),	// can send now
	.DIN(sddataout),			// data to send
	.DIN_VLD(sddatawe),			// data write enable
	// Input to BUS
	.DOUT(sddatain),			// data arriving from SPI
	.DOUT_VLD(sddatainready) );	// data available for read

// ----------------------------------------------------------------------------
// SPI write
// ----------------------------------------------------------------------------

wire [7:0] spisenddout;
bit spisendre = 1'b0;
wire spisendfull, spisendempty, spisendvalid;

spioutfifo SPIDataOutFIFO(
	.full(spisendfull),
	.din(din),
	.wr_en(buswe),
	.wr_clk(cpuclock), // Write using cpu clock
	.empty(spisendempty),
	.valid(spisendvalid),
	.dout(spisenddout),
	.rd_en(spisendre),
	.rd_clk(spibaseclock), // Read using UART base clock
	.rst(reset) );

bit [1:0] spiwritemode = 2'b00;

always @(posedge spibaseclock) begin
	if (reset) begin
		spiwritemode <= 2'b00;
	end else begin
		spisendre <= 1'b0;
		sddatawe <= 1'b0;
	
		unique case(spiwritemode)
			2'b00: begin // IDLE
				if (~spisendempty & sddataoutready) begin
					spisendre <= 1'b1;
					spiwritemode <= 2'b01; // WRITE
				end
			end
			2'b01: begin // WRITE
				if (spisendvalid) begin
					sddatawe <= 1'b1;
					sddataout <= spisenddout;
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
end

// ----------------------------------------------------------------------------
// SPI read
// ----------------------------------------------------------------------------

wire spircvfull, spircvvalid;
bit [7:0] spircvdin = 8'h00;
wire [7:0] spircvdout;
bit spircvre = 1'b0, spircvwe = 1'b0;

spiinfifo SPIDataInFIFO(
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

always @(posedge spibaseclock) begin
	if (reset) begin
		//
	end else begin
		spircvwe <= 1'b0;
	
		if (sddatainready & (~spisendfull)) begin
			spircvwe <= 1'b1;
			spircvdin <= sddatain;
		end
	end
end

bit readpending = 1'b0;
always @(posedge cpuclock) begin
	if (reset) begin
		readpending <= 1'b0;
	end else begin
		spircvre <= 1'b0;
	
		if (readpending == 1'b0) begin
			if (busre) begin
				dout <= 8'hFF;
				spircvre <= 1'b1;
				readpending <= 1'b1;
			end
		end else begin // readpending == 1'b1
			if (spircvvalid) begin
				dout <= spircvdout;
				readpending <= 1'b0;
			end
		end
	end
end

// Bus stall signal
assign busy = enable & ((busre | readpending) | (buswe & spisendfull));

endmodule
