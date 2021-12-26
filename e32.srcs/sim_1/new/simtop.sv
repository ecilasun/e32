`timescale 1ns / 1ps

module simtop();

// Virtual external FPGA wires connected to top module
logic fpgaexternalclock;
wire uart_rxd_out, uart_txd_in;

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
	.uart_txd_in(uart_txd_in) );

// External FPGA clock ticks at 100Mhz
always begin
	#5 fpgaexternalclock = ~fpgaexternalclock;
end

endmodule
