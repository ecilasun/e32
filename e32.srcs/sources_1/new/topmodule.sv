`timescale 1ns / 1ps

module topmodule(
	// FPGA external clock
	input wire sys_clock,
	// Device wires
	output wire uart_rxd_out,
	input  wire uart_txd_in,
	output wire spi_cs_n,
	output wire spi_mosi,
	input wire spi_miso,
	output wire spi_sck );

// ----------------------------------------------------------------------------
// Device wire interface
// ----------------------------------------------------------------------------

FPGADeviceWires wires(
	.uart_txd_in(uart_txd_in),
	.uart_rxd_out(uart_rxd_out),
	.spi_cs_n(spi_cs_n),
	.spi_mosi(spi_mosi),
	.spi_miso(spi_miso),
	.spi_sck(spi_sck) );

// ----------------------------------------------------------------------------
// Clock and reset generator
// ----------------------------------------------------------------------------

wire wallclock, cpuclock, uartbaseclock, spibaseclock;
wire devicereset, calib_done;

clockandresetgen ClockAndResetGenerator(
	.sys_clock_i(sys_clock),
	.wallclock(wallclock),
	.cpuclock(cpuclock),
	.uartbaseclock(uartbaseclock),
	.spibaseclock(spibaseclock),
	.devicereset(devicereset) );

FPGADeviceClocks clocks(
	.calib_done(calib_done),
	.cpuclock(cpuclock),
	.wallclock(wallclock),
	.uartbaseclock(uartbaseclock),
	.spibaseclock(spibaseclock) );

// ----------------------------------------------------------------------------
// AXI4 chain
// ----------------------------------------------------------------------------

wire [3:0] irq;

axi4 axi4chain(
	.ACLK(cpuclock),
	.ARESETn(~devicereset) );

axi4chain AXIChain(
	.axi4if(axi4chain),
	.clocks(clocks),
	.wires(wires),
	.irq(irq) );

// ----------------------------------------------------------------------------
// Master device (CPU)
// Reset vector points at B-RAM which contains the startup code
// ----------------------------------------------------------------------------

axi4cpu #(.RESETVECTOR(32'h10000000)) HART0(
	.axi4if(axi4chain),
	.clocks(clocks),
	.wires(wires),
	.irq(irq) );

endmodule
