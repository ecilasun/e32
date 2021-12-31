`timescale 1ns / 1ps

module topmodule(
	// FPGA external clock
	input wire sys_clock,
	// UART hardware
	output wire uart_rxd_out,
	input wire uart_txd_in,
	// SPI PMOD connection
	output wire spi_cs_n,
	output wire spi_mosi,
	input wire spi_miso,
	output wire spi_sck	);

// ----------------------------------------------------------------------------
// Clock and reset generator
// ----------------------------------------------------------------------------

wire wallclock, cpuclock, uartbaseclock, spibaseclock, devicereset;

clockandresetgen ClockAndResetGenerator(
	.sys_clock_i(sys_clock),
	.wallclock(wallclock),
	.cpuclock(cpuclock),
	.uartbaseclock(uartbaseclock),
	.spibaseclock(spibaseclock),
	.devicereset(devicereset) );

// ----------------------------------------------------------------------------
// AXI4 chain
// ----------------------------------------------------------------------------

wire [3:0] irq;

axi4 axi4chain(.ACLK(cpuclock), .ARESETn(~devicereset));

axi4chain AXIChain(
	.axi4if(axi4chain.SLAVE),
	.irq(irq),
	.uartbaseclock(uartbaseclock),
	.spibaseclock(spibaseclock),
	.uart_rxd_out(uart_rxd_out),
	.uart_txd_in(uart_txd_in),
	.spi_cs_n(spi_cs_n),
	.spi_mosi(spi_mosi),
	.spi_miso(spi_miso),
	.spi_sck(spi_sck) );

// ----------------------------------------------------------------------------
// Master device (CPU)
// ----------------------------------------------------------------------------

axi4cpu #(.RESETVECTOR(32'h10000000)) HART0(
	.axi4if(axi4chain.MASTER),
	.irq(irq) );

endmodule
