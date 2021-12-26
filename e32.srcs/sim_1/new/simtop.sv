`timescale 1ns / 1ps

module simtop();

// Virtual external FPGA wires connected to top module
logic fpgaexternalclock;
wire uart_rxd_out, uart_txd_in;
wire spi_cs_n;
wire spi_mosi, spi_miso;
wire spi_sck;

// Startup message and setup
initial begin
	fpgaexternalclock = 1'b0;
	$display("E32 test start");
end

// The testbench will loop uart output back to input
// This ensures that after startup we start getting
// hardware interrupts and can see the interrupt handler,
// if installed and enabled, running on the CPU.
assign uart_txd_in = uart_rxd_out;

// Top module instance
toplevel toplevelinstance(
    .sys_clock(fpgaexternalclock),
    .uart_rxd_out(uart_rxd_out),
	.uart_txd_in(uart_txd_in),
	.spi_cs_n(spi_cs_n),
	.spi_mosi(spi_mosi),
	.spi_miso(spi_miso),
	.spi_sck(spi_sck) );

// External FPGA clock ticks at 100Mhz
always begin
	#5 fpgaexternalclock = ~fpgaexternalclock;
end

endmodule
