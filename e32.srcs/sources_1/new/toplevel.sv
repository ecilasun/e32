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
wire [31:0] busdata;
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
// Bus arbiter
// ----------------------------------------------------------------------------

wire gnt3, gnt2, gnt1, gnt0;
wire req3, req2, req1, req0;
arbiter BusArbiter(
  .clk(cpuclock),
  .rst(reset),
  .req3(req3),
  .req2(req2),
  .req1(req1),
  .req0(req0),
  .gnt3(gnt3),
  .gnt2(gnt2),
  .gnt1(gnt1),
  .gnt0(gnt0)
);

assign req0 = busre | (|buswe);	// Client 0
assign req1 = 1'b0;
assign req2 = 1'b0;
assign req3 = 1'b0;

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
	.busdata(busdata),
	.buswe(buswe),
	.busre(busre),
	.busbusy(busbusy) );

// ----------------------------------------------------------------------------
// CPU Core #0, reset vector at 0x10000000
// ----------------------------------------------------------------------------

cpu #( .RESETVECTOR(32'h10000000) ) Core0
	(
	.cpuclock(cpuclock),
	.reset(reset),
	.irqtrigger(irqtrigger),
	.irqlines(irqlines),
	.busaddress(busaddress),
	.busdata(busdata),
	.busre(busre),
	.buswe(buswe),
	.busbusy(busbusy | (req0 & (~gnt0))) ); // Hold bus on read bus stall or if we're asking for access and can't get it granted yet

endmodule
