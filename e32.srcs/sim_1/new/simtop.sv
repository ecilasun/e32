`timescale 1ns / 1ps

module simtop();

logic fpgaexternalclock;

initial begin
	fpgaexternalclock = 1'b0;
	$display("e32 started up");
end

wire uart_rxd_out, uart_txd_in;

assign uart_txd_in = 1'b0;

toplevel toplevelinstance(
    .sys_clock(fpgaexternalclock),
    .uart_rxd_out(uart_rxd_out),
	.uart_txd_in(uart_txd_in) );

// External clock ticks at 100Mhz
always begin
	#5 fpgaexternalclock = ~fpgaexternalclock;
end

endmodule
