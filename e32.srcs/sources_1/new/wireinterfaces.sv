interface FPGADeviceWires (
		output uart_rxd_out,
		input uart_txd_in,
		output spi_cs_n,
		output spi_mosi,
		input spi_miso,
		output spi_sck );

	modport DEFAULT (
		output uart_rxd_out,
		input uart_txd_in,
		output spi_cs_n,
		output spi_mosi,
		input spi_miso,
		output spi_sck );

endinterface


interface FPGADeviceClocks (
		input calib_done,
		input cpuclock,
		input wallclock,
		input uartbaseclock,
		input spibaseclock,
		input gpubaseclock,
		input videoclock );

	modport DEFAULT (
		input calib_done,
		input cpuclock,
		input wallclock,
		input uartbaseclock,
		input spibaseclock,
		input gpubaseclock,
		input videoclock );

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
