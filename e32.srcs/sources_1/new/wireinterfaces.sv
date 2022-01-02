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
		input spibaseclock );

	modport DEFAULT (
		input calib_done,
		input cpuclock,
		input wallclock,
		input uartbaseclock,
		input spibaseclock );

endinterface
