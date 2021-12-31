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
	output wire spi_sck,
	// DDR3 hardware
    output wire [13:0] ddr3_addr,
    output wire [2:0] ddr3_ba,
    output wire ddr3_cas_n,
    output wire [0:0] ddr3_ck_n,
    output wire [0:0] ddr3_ck_p,
    output wire [0:0] ddr3_cke,
    output wire ddr3_ras_n,
    output wire ddr3_reset_n,
    output wire ddr3_we_n,
    inout wire [15:0] ddr3_dq,
    inout wire [1:0] ddr3_dqs_n,
    inout wire [1:0] ddr3_dqs_p,
	output wire [0:0] ddr3_cs_n,
    output wire [1:0] ddr3_dm,
    output wire [0:0] ddr3_odt );

// ----------------------------------------------------------------------------
// Clock and reset generator
// ----------------------------------------------------------------------------

wire wallclock, cpuclock, uartbaseclock, spibaseclock, clk_ddr_w, clk_ddr_dqs_w, clk_ref_w, devicereset;

clockandresetgen ClockAndResetGenerator(
	.sys_clock_i(sys_clock),
	.wallclock(wallclock),
	.cpuclock(cpuclock),
	.uartbaseclock(uartbaseclock),
	.spibaseclock(spibaseclock),
	.clk_ddr_w(clk_ddr_w),
	.clk_ddr_dqs_w(clk_ddr_dqs_w),
	.clk_ref_w(clk_ref_w),
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
	.spi_sck(spi_sck),
	.clk_ddr_w(clk_ddr_w),
	.clk_ddr_dqs_w(clk_ddr_dqs_w),
	.clk_ref_w(clk_ref_w),
    .ddr3_addr(ddr3_addr),
    .ddr3_ba(ddr3_ba),
    .ddr3_cas_n(ddr3_cas_n),
    .ddr3_ck_n(ddr3_ck_n),
    .ddr3_ck_p(ddr3_ck_p),
    .ddr3_cke(ddr3_cke),
    .ddr3_ras_n(ddr3_ras_n),
    .ddr3_reset_n(ddr3_reset_n),
    .ddr3_we_n(ddr3_we_n),
    .ddr3_dq(ddr3_dq),
    .ddr3_dqs_n(ddr3_dqs_n),
    .ddr3_dqs_p(ddr3_dqs_p),
	.ddr3_cs_n(ddr3_cs_n),
    .ddr3_dm(ddr3_dm),
    .ddr3_odt(ddr3_odt) );

// ----------------------------------------------------------------------------
// Master device (CPU)
// ----------------------------------------------------------------------------

axi4cpu #(.RESETVECTOR(32'h10000000)) HART0(
	.axi4if(axi4chain.MASTER),
	.irq(irq) );

endmodule
