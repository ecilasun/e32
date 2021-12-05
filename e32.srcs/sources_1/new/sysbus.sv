`timescale 1ns / 1ps

`include "devices.vh"

module sysbus(
	// Module control
	input wire wallclock,
	input wire cpuclock,
	input wire reset,
	// UART
	output wire uart_rxd_out,
	input wire uart_txd_in,
	// Interrupts
	output wire irqtrigger,
	output wire [3:0] irqlines,
	// Bus control
	input wire [31:0] busaddress,
	input wire [31:0] din,
	output logic [31:0] dout = 32'd0,
	input wire [3:0] buswe,
	input wire busre,
	output wire busbusy );

// ----------------------------------------------------------------------------
// Memory mapped devices
// ----------------------------------------------------------------------------

wire [`DEVICE_COUNT-1:0] deviceSelect = {
	{busaddress[31:28], busaddress[5:2]} == 8'b1000_0011 ? 1'b1 : 1'b0,	// 06: 0x8xxxxx0C SPI read/write port					+DEV_SPIRW
	{busaddress[31:28], busaddress[5:2]} == 8'b1000_0010 ? 1'b1 : 1'b0,	// 05: 0x8xxxxx08 UART read/write port					+DEV_UARTRW
	{busaddress[31:28], busaddress[5:2]} == 8'b1000_0001 ? 1'b1 : 1'b0,	// 04: 0x8xxxxx04 UART incoming queue byte available	+DEV_UARTBYTEAVAILABLE
	{busaddress[31:28], busaddress[5:2]} == 8'b1000_0000 ? 1'b1 : 1'b0,	// 03: 0x8xxxxx00 UART outgoing queue full				+DEV_UARTSENDFIFOFULL
	(busaddress[31:28]==4'b0011) ? 1'b1 : 1'b0,							// 02: 0x30000000 - 0x30010000 - P-RAM (64Kbytes)		+DEV_PRAM
	(busaddress[31:28]==4'b0010) ? 1'b1 : 1'b0,							// 02: 0x20000000 - 0x20010000 - G-RAM (64Kbytes)		+DEV_GRAM
	(busaddress[31:28]==4'b0001) ? 1'b1 : 1'b0,							// 01: 0x10000000 - 0x10010000 - S-RAM (64Kbytes)		+DEV_SRAM
	(busaddress[31:28]==4'b0000) ? 1'b1 : 1'b0							// 00: 0x00000000 - 0x0FFFFFFF - DDR3 (256Mbytes)		+DEV_DDR3
};

// ----------------------------------------------------------------------------
// UART
// ----------------------------------------------------------------------------

// Single byte write, therefore we collapse buswe into 1 bit via wide OR
wire uartwe = deviceSelect[`DEV_UARTRW] ? (|buswe) : 1'b0;
// Incoming data from UART
wire [31:0] uartdout;
// Status signals
wire uartreadbusy, uartwritebusy, uartrcvempty;

uartdriver UARTDevice(
	.deviceSelect(deviceSelect),
	.clk10(wallclock),
	.cpuclock(cpuclock),
	.reset(reset),
	.buswe(uartwe),
	.busre(busre),
	.uartreadbusy(uartreadbusy),
	.uartwritebusy(uartwritebusy),
	.din(din),
	.dout(uartdout),
	.uartrcvempty(uartrcvempty),
	.uart_rxd_out(uart_rxd_out),
	.uart_txd_in(uart_txd_in) );

// ----------------------------------------------------------------------------
// S-RAM (64Kbytes, also acts as boot ROM) - Scratch Memory
// ----------------------------------------------------------------------------

wire sramre = deviceSelect[`DEV_SRAM] ? busre : 1'b0;
wire [3:0] sramwe = deviceSelect[`DEV_SRAM] ? buswe : 4'h0;
wire [31:0] sramdin = deviceSelect[`DEV_SRAM] ? din : 32'd0;
wire [13:0] sramaddr = deviceSelect[`DEV_SRAM] ? busaddress[15:2] : 0;
wire [31:0] sramdout;

scratchram SRAMBOOTRAMDevice(
	.addra(sramaddr),
	.clka(cpuclock),
	.dina(sramdin),
	.douta(sramdout),
	.ena(deviceSelect[`DEV_SRAM] & (sramre | (|sramwe))),
	.wea(sramwe) );

// ----------------------------------------------------------------------------
// External interrupts
// ----------------------------------------------------------------------------

// TODO: Generate interrupt bits for more devices
// Currently UART will keep triggerring an interrupt when FIFO has anything in it until it's completely drained
// NOTE: As we're servicing interrupts, further interrupts are disabled so it's not an issue to have IRQ high at all times
assign irqlines = {3'b000, ~uartrcvempty};
// Wide-OR to trigger when any interrupt is high.
// NOTE: Watch out for incoming clock domains here; irqtrigger is used by cpuclock domain!
assign irqtrigger = |irqlines;

// ----------------------------------------------------------------------------
// Data assignment
// ----------------------------------------------------------------------------

// Based on device, set the incoming data for CPU reads.
always_comb begin
	case (1'b1)
		deviceSelect[`DEV_SRAM]:					dout = sramdout;		// Read from S-RAM
		deviceSelect[`DEV_UARTRW],
		deviceSelect[`DEV_UARTBYTEAVAILABLE],
		deviceSelect[`DEV_UARTSENDFIFOFULL]:		dout = uartdout;		// Read from UART_data or UART_status
	endcase
end

// Busy is high when bus is not able to respond to requests just yet
assign busbusy = (deviceSelect[`DEV_UARTRW] & (uartreadbusy|uartwritebusy));// | (deviceSelect[somedevice]&(rbusy|wbusy)) | (...)

endmodule
