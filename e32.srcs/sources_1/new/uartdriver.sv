`timescale 1ns / 1ps

`include "devices.vh"

module uartdriver(
	input wire [`DEVICE_COUNT-1:0] deviceSelect,
	input wire clk10,
	input wire cpuclock,
	input wire reset,
	output wire busy,
	input wire buswe,
	input wire busre,
	input wire [31:0] din,
	output bit [31:0] dout = 32'd0,
	output wire uartrcvempty,
	output wire uart_rxd_out,
	input wire uart_txd_in);

// ----------------------------------------------------------------------------
// UART Transmitter
// ----------------------------------------------------------------------------

bit transmitbyte = 1'b0;
bit [7:0] datatotransmit = 8'h00;
wire uarttxbusy;

async_transmitter UART_transmit(
	.clk(clk10),
	.TxD_start(transmitbyte),
	.TxD_data(datatotransmit),
	.TxD(uart_rxd_out),
	.TxD_busy(uarttxbusy) );

wire [7:0] uartsenddout;
bit uartsendre = 1'b0;
wire uartsendfull, uartsendempty, uartsendvalid;

uartoutfifo UARTDataOutFIFO(
	.full(uartsendfull),
	.din(din[7:0]),
	.wr_en(buswe),
	.wr_clk(cpuclock), // Write using cpu clock
	.empty(uartsendempty),
	.valid(uartsendvalid),
	.dout(uartsenddout),
	.rd_en(uartsendre),
	.rd_clk(clk10), // Read using UART base clock
	.rst(reset) );

bit [1:0] uartwritemode = 2'b00;

always @(posedge clk10) begin
	uartsendre <= 1'b0;
	transmitbyte <= 1'b0;
	unique case(uartwritemode)
		2'b00: begin // IDLE
			if (~uartsendempty & (~uarttxbusy)) begin
				uartsendre <= 1'b1;
				uartwritemode <= 2'b01; // WRITE
			end
		end
		2'b01: begin // WRITE
			if (uartsendvalid) begin
				transmitbyte <= 1'b1;
				datatotransmit <= uartsenddout;
				uartwritemode <= 2'b10; // FINALIZE
			end
		end
		2'b10: begin // FINALIZE
			// Need to give UARTTX one clock to
			// kick 'busy' for any adjacent
			// requests which didn't set busy yet
			uartwritemode <= 2'b00; // IDLE
		end
	endcase
end

// ----------------------------------------------------------------------------
// UART Receiver
// ----------------------------------------------------------------------------

wire uartbyteavailable;
wire [7:0] uartbytein;

async_receiver UART_receive(
	.clk(clk10),
	.RxD(uart_txd_in),
	.RxD_data_ready(uartbyteavailable),
	.RxD_data(uartbytein),
	.RxD_idle(),
	.RxD_endofpacket() );

wire uartrcvfull, uartrcvvalid;
bit [7:0] uartrcvdin = 8'h00;
wire [7:0] uartrcvdout;
bit uartrcvre = 1'b0, uartrcvwe = 1'b0;

uartinfifo UARTDataInFIFO(
	.full(uartrcvfull),
	.din(uartrcvdin),
	.wr_en(uartrcvwe),
	.wr_clk(clk10),
	.empty(uartrcvempty),
	.dout(uartrcvdout),
	.rd_en(uartrcvre),
	.valid(uartrcvvalid),
	.rd_clk(cpuclock),
	.rst(reset) );

// Record all incoming data from UART
// NOTE: There is no FIFO full protection for
// simplicity; software _must_ read all it can
// as quick as possible
// (Use the DEV_UARTBYTEAVAILABLE port to see if more data is pending)
always @(posedge clk10) begin
	uartrcvwe <= 1'b0;
	// NOTE: Any byte that won't fit into the FIFO will be dropped
	// Make sure to consume them quickly on arrival!
	if (uartbyteavailable & (~uartsendfull)) begin
		uartrcvwe <= 1'b1;
		uartrcvdin <= uartbytein;
	end
end

// Pull data from the FIFO whenever a read request is placed
// FIFO is fallthrough so it will signal valid as soon as it
// sees the read enable.
always @(posedge cpuclock) begin

	uartrcvre <= 1'b0;

	// Route read requests to either input FIFO or status data
	if (busre) begin
		case (1'b1)
			deviceSelect[`DEV_UARTRW]: begin
				dout <= 32'd0; // Will read zero if FIFO is empty
				uartrcvre <= (~uartrcvempty);
			end
			deviceSelect[`DEV_UARTBYTEAVAILABLE]: begin
				dout <= {31'd0, (~uartrcvempty)};
				uartrcvre <= 1'b0;
			end
			deviceSelect[`DEV_UARTSENDFIFOFULL]: begin
				dout <= {31'd0, uartsendfull};
				uartrcvre <= 1'b0;
			end
		endcase
	end

	if (uartrcvvalid) begin // NOTE: Read FIFO is fallthrough, meaning result should be here on next clock
		dout <= {24'd0, uartrcvdout};
	end
end

// Bus stall signals

// Type one: block when there's no incoming data and we're reading, or block when output fifo is full and we're writing
//assign busy = deviceSelect[`DEV_UARTRW] & ((busre & uartrcvempty) | (buswe & uartsendfull));

// Type two: only block when output fifo is full and we're writing, reads return zero when fifo is empty
assign busy = deviceSelect[`DEV_UARTRW] & (buswe & uartsendfull);

endmodule
