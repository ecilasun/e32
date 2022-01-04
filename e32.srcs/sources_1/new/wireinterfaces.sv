interface FPGADeviceWires (
		output uart_rxd_out,
		input uart_txd_in,
		output spi_cs_n,
		output spi_mosi,
		input spi_miso,
		output spi_sck,
		// DDR3
		output ddr3_reset_n,
		output [0:0] ddr3_cke,
		output [0:0] ddr3_ck_p, 
		output [0:0] ddr3_ck_n,
		output [0:0] ddr3_cs_n,
		output ddr3_ras_n, 
		output ddr3_cas_n, 
		output ddr3_we_n,
		output [2:0] ddr3_ba,
		output [13:0] ddr3_addr,
		output [0:0] ddr3_odt,
		output [1:0] ddr3_dm,
		inout [1:0] ddr3_dqs_p,
		inout [1:0] ddr3_dqs_n,
		inout [15:0] ddr3_dq );

	modport DEFAULT (
		output uart_rxd_out,
		input uart_txd_in,
		output spi_cs_n,
		output spi_mosi,
		input spi_miso,
		output spi_sck,
		output ddr3_reset_n,
		output ddr3_cke,
		output ddr3_ck_p, 
		output ddr3_ck_n,
		output ddr3_cs_n,
		output ddr3_ras_n, 
		output ddr3_cas_n, 
		output ddr3_we_n,
		output ddr3_ba,
		output ddr3_addr,
		output ddr3_odt,
		output ddr3_dm,
		inout ddr3_dqs_p,
		inout ddr3_dqs_n,
		inout ddr3_dq );

endinterface


interface FPGADeviceClocks (
		input calib_done,
		input cpuclock,
		input wallclock,
		input uartbaseclock,
		input spibaseclock,
		input gpubaseclock,
		input videoclock,
		input clk_sys_i,
		input clk_ref_i );

	modport DEFAULT (
		input calib_done,
		input cpuclock,
		input wallclock,
		input uartbaseclock,
		input spibaseclock,
		input gpubaseclock,
		input videoclock,
		input clk_sys_i,
		input clk_ref_i );

endinterface

interface GPUDataOutput(
	// DVI
	output [3:0] DVI_R,
	output [3:0] DVI_G,
	output [3:0] DVI_B,
	output DVI_HS,
	output DVI_VS,
	output DVI_DE,
	output DVI_CLK );

	modport DEFAULT (
		output DVI_R,
		output DVI_G,
		output DVI_B,
		output DVI_HS,
		output DVI_VS,
		output DVI_DE,
		output DVI_CLK );

endinterface
