`include "devices.vh"

module sysbus(
	// Module control
	input wire wallclock,
	input wire cpuclock,
	input wire reset,
	output wire [`DEVICE_COUNT-1:0] deviceSelect,
	// UART
	output wire uart_rxd_out,
	input wire uart_txd_in,
	// Bus control
	input wire [31:0] addrs,
	input wire [31:0] din,
	output logic [31:0] dout = 32'd0,
	input wire [3:0] buswe,
	input wire busre,
	// UART port
	output wire uartwe,
	output wire uartre,
	output wire [31:0] uartdin,
	input wire [31:0] uartdout,
	input wire uartbusy,
	input wire uartrcvempty,
	// SRAM port
	output wire sramre,
	output wire [3:0] sramwe,
	output wire [31:0] sramdin,
	output wire [13:0] sramaddr,
	input wire [31:0] sramdout );

// ----------------------------------------------------------------------------
// Memory mapped device select line
// ----------------------------------------------------------------------------

assign deviceSelect = {
	(addrs[31:28]==4'b1000) ? 1'b1 : 1'b0,						// 02: 0x8xxxxxxx Any UART device						+DEV_UARTANY
	(addrs[31:28]==4'b0001) ? 1'b1 : 1'b0,						// 01: 0x10000000 - 0x10010000 - S-RAM (64Kbytes)		+DEV_SRAM
	(addrs[31:28]==4'b0000) ? 1'b1 : 1'b0						// 00: 0x00000000 - 0x0FFFFFFF - DDR3 (256Mbytes)		-DEV_DDR3
};

// ----------------------------------------------------------------------------
// UART control
// ----------------------------------------------------------------------------

assign uartre = deviceSelect[`DEV_UARTANY] ? busre : 1'b0;
assign uartwe = deviceSelect[`DEV_UARTANY] ? (|buswe) : 1'b0;
assign uartdin = deviceSelect[`DEV_UARTANY] ? din : 32'd0;

// ----------------------------------------------------------------------------
// S-RAM control
// ----------------------------------------------------------------------------

assign sramre = deviceSelect[`DEV_SRAM] ? busre : 1'b0;
assign sramwe = deviceSelect[`DEV_SRAM] ? buswe : 4'h0;
assign sramdin = deviceSelect[`DEV_SRAM] ? din : 32'd0;
assign sramaddr = deviceSelect[`DEV_SRAM] ? addrs[15:2] : 0;

// ----------------------------------------------------------------------------
// Bus data out
// ----------------------------------------------------------------------------

always_comb begin
	case (1'b1)
		deviceSelect[`DEV_SRAM]:		dout = sramdout;		// Read from S-RAM
		deviceSelect[`DEV_UARTANY]:		dout = uartdout;		// Read from any UART address
	endcase
end

endmodule
