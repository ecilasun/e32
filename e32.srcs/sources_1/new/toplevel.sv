`timescale 1ns / 1ps

`default_nettype none

`include "devices.vh"

module toplevel(
	input wire sys_clock,
	output wire uart_rxd_out,
	input wire uart_txd_in);

// ------------------------
// Clock + reset generator
// ------------------------

wire wallclock, cpuclock, reset;

clockandresetgen ClockAndResetGenerator(
	.sys_clock_i(sys_clock),
	.wallclock(wallclock),
	.cpuclock(cpuclock),
	.devicereset(reset) );

// ------------------------
// System bus and attached devices
// ------------------------

wire [31:0] busaddress;
wire [31:0] busdata;
wire [3:0] buswe;
wire busre, busbusy;
wire irqtrigger;
wire [3:0] irqlines;

sysbus SystemBus(
	.wallclock(wallclock),
	.cpuclock(cpuclock),
	.reset(reset),
	// CPU
	//input wire ifetch, // High when fetching instructions, low otherwise
	//input wire dcacheicachesync, // High when we need to flush D$ to memory
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

// ------------------------
// CPU
// ------------------------

cpu Core0(
	.cpuclock(cpuclock),
	.reset(reset),
	.irqtrigger(irqtrigger),
	.irqlines(irqlines),
	.busaddress(busaddress),
	.busdata(busdata),
	.busre(busre),
	.buswe(buswe),
	.busbusy(busbusy) );

endmodule
