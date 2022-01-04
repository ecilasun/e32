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
	output wire spi_sck,
	// DVI
	output wire [3:0] DVI_R,
	output wire [3:0] DVI_G,
	output wire [3:0] DVI_B,
	output wire DVI_HS,
	output wire DVI_VS,
	output wire DVI_DE,
	output wire DVI_CLK );

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

GPUDataOutput gpudata(
	.DVI_R(DVI_R),
	.DVI_G(DVI_G),
	.DVI_B(DVI_B),
	.DVI_HS(DVI_HS),
	.DVI_VS(DVI_VS),
	.DVI_DE(DVI_DE),
	.DVI_CLK(DVI_CLK) );

// ----------------------------------------------------------------------------
// Clock and reset generator
// ----------------------------------------------------------------------------

wire wallclock, cpuclock, uartbaseclock, spibaseclock;
wire gpubaseclock, videoclock;
wire devicereset, calib_done;

clockandresetgen ClockAndResetGenerator(
	.sys_clock_i(sys_clock),
	.wallclock(wallclock),
	.cpuclock(cpuclock),
	.uartbaseclock(uartbaseclock),
	.spibaseclock(spibaseclock),
	.gpubaseclock(gpubaseclock),
	.videoclock(videoclock),
	.devicereset(devicereset) );

FPGADeviceClocks clocks(
	.calib_done(calib_done),
	.cpuclock(cpuclock),
	.wallclock(wallclock),
	.uartbaseclock(uartbaseclock),
	.spibaseclock(spibaseclock),
	.gpubaseclock(gpubaseclock),
	.videoclock(videoclock) );

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
	.gpudata(gpudata),
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
