`timescale 1ns / 1ps

module simtop( );

wire uart_rxd_out;
wire uart_txd_in;
wire spi_cs_n, spi_mosi, spi_miso, spi_sck;

logic sys_clock;

initial begin
	sys_clock <= 1'b0;
end

// The testbench will loop uart output back to input
// This ensures that after startup we start getting
// hardware interrupts and can see the interrupt handler,
// if installed and enabled, running on the CPU.
assign uart_txd_in = uart_rxd_out;

// Loopback the SPI data
assign spi_miso = spi_mosi;

topmodule topmoduleinstance(
	sys_clock,
	uart_rxd_out,
	uart_txd_in,
	spi_cs_n,
	spi_mosi,
	spi_miso,
	spi_sck	);

always #10 sys_clock = ~sys_clock; // 100MHz

endmodule
