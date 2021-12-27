`timescale 1ns / 1ps

`include "devices.vh"

module ddr3driver(
	input wire ddr3sysclk,
	input wire ddr3refclk,
	input wire cpuclock,
	input wire reset,
	input wire enable,
	output wire busy,
	input wire buswe,
	input wire busre,
	input wire [31:0] din,
	output bit [31:0] dout = 32'd0
	// TODO: DDR3 external wires
	);

// ----------------------------------------------------------------------------
// DDR3 Device
// ----------------------------------------------------------------------------

// TODO:

// ----------------------------------------------------------------------------
// DDR3 Write
// ----------------------------------------------------------------------------

// TODO:

// ----------------------------------------------------------------------------
// DDR3 Read
// ----------------------------------------------------------------------------

// TODO:

// Bus stall signal
assign busy = 1'b0;//enable & ((busre | readpending) | (buswe & spisendfull));

endmodule
