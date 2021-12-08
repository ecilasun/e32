`timescale 1ns / 1ps

`default_nettype none

`include "devices.vh"

module toplevel(
	input wire sys_clock,
	output wire uart_rxd_out,
	input wire uart_txd_in);

// ----------------------------------------------------------------------------
// Internal wiring
// ----------------------------------------------------------------------------

// Clock/reset wires
wire wallclock, cpuclock, reset;

// Bus control wires
wire [31:0] busaddress;
wire [31:0] din;
wire [31:0] dout;
wire [3:0] buswe;
wire busre, busbusy;

// Interrupt wires
wire irqtrigger;
wire [3:0] irqlines;

// ----------------------------------------------------------------------------
// Clock + reset generator
// ----------------------------------------------------------------------------

clockandresetgen ClockAndResetGenerator(
	.sys_clock_i(sys_clock),
	.wallclock(wallclock),
	.cpuclock(cpuclock),
	.devicereset(reset) );

// ----------------------------------------------------------------------------
// Arbiter - WiP
// ----------------------------------------------------------------------------

/*wire [3:0] req;
wire [2:0] gnt;

arbiter BusArbiter(
	.req(req),
	.gnt(gnt) );

// Request lines from devices
assign req = {1'b0, 1'b0, 1'b0, busre | (|buswe)};*/

// ----------------------------------------------------------------------------
// System bus and attached devices
// ----------------------------------------------------------------------------

sysbus SystemBus(
	.wallclock(wallclock),
	.cpuclock(cpuclock),
	.reset(reset),
	// UART
	.uart_rxd_out(uart_rxd_out),
	.uart_txd_in(uart_txd_in),
	// Interrupts
	.irqtrigger(irqtrigger),
	.irqlines(irqlines),
	// Bus control
	.busaddress(busaddress),
	.din(din),
	.dout(dout),
	.buswe(buswe),
	.busre(busre),
	.busbusy(busbusy) );

// ----------------------------------------------------------------------------
// CPU HART#0, reset vector at 0x10000000
// ----------------------------------------------------------------------------

cpu #( .RESETVECTOR(32'h10000000) ) HART0
	(
	.cpuclock(cpuclock),
	.reset(reset),
	.irqtrigger(irqtrigger),
	.irqlines(irqlines),
	.busaddress(busaddress),
	.din(dout),
	.dout(din),
	.busre(busre),
	.buswe(buswe),
	.busbusy(busbusy));// | (req[0]&(~gnt[0]))) );

endmodule
