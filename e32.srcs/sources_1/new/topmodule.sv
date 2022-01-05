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
	output wire DVI_CLK,
    // DDR3
    output wire ddr3_reset_n,
    output wire [0:0] ddr3_cke,
    output wire [0:0] ddr3_ck_p, 
    output wire [0:0] ddr3_ck_n,
    output wire [0:0] ddr3_cs_n,
    output wire ddr3_ras_n, 
    output wire ddr3_cas_n, 
    output wire ddr3_we_n,
    output wire [2:0] ddr3_ba,
    output wire [13:0] ddr3_addr,
    output wire [0:0] ddr3_odt,
    output wire [1:0] ddr3_dm,
    inout wire [1:0] ddr3_dqs_p,
    inout wire [1:0] ddr3_dqs_n,
    inout wire [15:0] ddr3_dq );

// ----------------------------------------------------------------------------
// Device wire interface
// ----------------------------------------------------------------------------

wire ui_clk;

FPGADeviceWires wires(
	.uart_txd_in(uart_txd_in),
	.uart_rxd_out(uart_rxd_out),
	.spi_cs_n(spi_cs_n),
	.spi_mosi(spi_mosi),
	.spi_miso(spi_miso),
	.spi_sck(spi_sck),
    // DDR3
    .ddr3_reset_n(ddr3_reset_n),
    .ddr3_cke(ddr3_cke),
    .ddr3_ck_p(ddr3_ck_p), 
    .ddr3_ck_n(ddr3_ck_n),
    .ddr3_cs_n(ddr3_cs_n),
    .ddr3_ras_n(ddr3_ras_n), 
    .ddr3_cas_n(ddr3_cas_n), 
    .ddr3_we_n(ddr3_we_n),
    .ddr3_ba(ddr3_ba),
    .ddr3_addr(ddr3_addr),
    .ddr3_odt(ddr3_odt),
    .ddr3_dm(ddr3_dm),
    .ddr3_dqs_p(ddr3_dqs_p),
    .ddr3_dqs_n(ddr3_dqs_n),
    .ddr3_dq(ddr3_dq) );

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
wire clk_sys_i, clk_ref_i;
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
	.clk_sys_i(clk_sys_i),
	.clk_ref_i(clk_ref_i),
	.devicereset(devicereset) );

FPGADeviceClocks clocks(
	.calib_done(calib_done),
	.cpuclock(ui_clk),//cpuclock), // Bus/CPU clock taken over by DDR3 generated clock
	.wallclock(wallclock),
	.uartbaseclock(uartbaseclock),
	.spibaseclock(spibaseclock),
	.gpubaseclock(gpubaseclock),
	.videoclock(videoclock),
	.clk_sys_i(clk_sys_i),
	.clk_ref_i(clk_ref_i) );

// ----------------------------------------------------------------------------
// AXI4 chain
// ----------------------------------------------------------------------------

wire [3:0] irq;
wire calib_done;

axi4 axi4chain(
	.ACLK(ui_clk),
	.ARESETn(~devicereset) );

axi4chain AXIChain(
	.axi4if(axi4chain),
	.clocks(clocks),
	.wires(wires),
	.gpudata(gpudata),
	.irq(irq),
	.calib_done(calib_done),
	.ui_clk(ui_clk) );

// ----------------------------------------------------------------------------
// Master device (CPU)
// Reset vector points at B-RAM which contains the startup code
// ----------------------------------------------------------------------------

axi4cpu #(.RESETVECTOR(32'h10000000)) HART0(
	.axi4if(axi4chain),
	.clocks(clocks),
	.wires(wires),
	.irq(irq),
	.calib_done(calib_done) );

endmodule
