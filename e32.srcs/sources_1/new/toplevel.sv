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
wire [`DEVICE_COUNT-1:0] deviceSelect;

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
// UART
// ----------------------------------------------------------------------------

wire uartwe;
wire uartre;
wire [31:0] uartdin;
wire [31:0] uartdout;
wire uartbusy;
wire uartrcvempty;

uartdriver UARTDevice(
	.deviceSelect(deviceSelect),
	.clk10(wallclock),
	.cpuclock(cpuclock),
	.reset(reset),
	.busy(uartbusy),
	.buswe(uartwe),
	.busre(uartre),
	.din(uartdin),
	.dout(uartdout),
	.uartrcvempty(uartrcvempty),
	.uart_rxd_out(uart_rxd_out),
	.uart_txd_in(uart_txd_in) );

// ----------------------------------------------------------------------------
// S-RAM (64Kbytes, also acts as boot ROM) - Scratch Memory
// ----------------------------------------------------------------------------

wire sramre;
wire [3:0] sramwe;
wire [31:0] sramdin;
wire [13:0] sramaddr;
wire [31:0] sramdout;

scratchram SRAMBOOTRAMDevice(
	.addra(sramaddr),
	.clka(cpuclock),
	.dina(sramdin),
	.douta(sramdout),
	.ena(sramre | (|sramwe)),
	.wea(sramwe) );

// ----------------------------------------------------------------------------
// System bus and attached devices
// ----------------------------------------------------------------------------

sysbus SystemBus(
	.wallclock(wallclock),
	.cpuclock(cpuclock),
	.reset(reset),
	.deviceSelect(deviceSelect),
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
	.busbusy(busbusy),
	// UART port
	.uartwe(uartwe),
	.uartre(uartre),
	.uartdin(uartdin),
	.uartdout(uartdout),
	.uartbusy(uartbusy),
	.uartrcvempty(uartrcvempty),
	// SRAM port
	.sramre(sramre),
	.sramwe(sramwe),
	.sramdin(sramdin),
	.sramaddr(sramaddr),
	.sramdout(sramdout) );

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
