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
wire [31:0] busaddress0;
wire [31:0] busaddress1;
wire [31:0] din0;
wire [31:0] din1;
wire [31:0] dout;
wire [3:0] buswe0;
wire [3:0] buswe1;
wire busre0;
wire busre1;
wire busbusy;
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

wire [3:0] busreq;
wire [3:0] busgnt;

wire [31:0] busaddress = busgnt[0] ? busaddress0 : busaddress1;
wire [31:0] din = busgnt[0] ? din0 : din1;
wire [3:0] buswe = busgnt[0] ? buswe0 : buswe1;
wire busre = busgnt[0] ? busre0 : busre1;

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
	// Bus access
	.busreq(busreq),
	.busgnt(busgnt),
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
// CPU HART#0
// Primary CPU
// Boots the system, with reset vector set at 0x10000000
// ----------------------------------------------------------------------------

cpu #( .RESETVECTOR(32'h10000000) ) HART0
	(
	.cpuclock(cpuclock),
	.reset(reset),
	.irqtrigger(irqtrigger),
	.irqlines(irqlines),
	.busreq(busreq[0]),
	.busgnt(busgnt[0]),
	.busaddress(busaddress0),
	.din(dout),
	.dout(din0),
	.busre(busre0),
	.buswe(buswe0),
	.busbusy(busbusy | busgnt[1]) );

// ----------------------------------------------------------------------------
// CPU HART#1
// Secondary CPU
// Spins on a WFI instruction at startup, with reset vector set at 0x1000A000
// ----------------------------------------------------------------------------

/*cpu #( .RESETVECTOR(32'h1000A000) ) HART1
	(
	.cpuclock(cpuclock),
	.reset(reset),
	.irqtrigger(irqtrigger),
	.irqlines(irqlines),
	.busreq(busreq[1]),
	.busgnt(busgnt[1]),
	.busaddress(busaddress1),
	.din(dout),
	.dout(din1),
	.busre(busre1),
	.buswe(buswe1),
	.busbusy(busbusy | busgnt[0]) );*/

// ----------------------------------------------------------------------------
// CPU HART#1/2/3
// Secondary CPUs
// TBD: placeholder wires for now
// ----------------------------------------------------------------------------

assign busreq[1] = 1'b0;
assign busaddress1 = 32'd0;
assign din1 = 32'd0;
assign busre1 = 1'b0;
assign buswe1 = 4'h0;

assign busreq[2] = 1'b0;
//assign busaddress2 = 32'd0;
//assign din2 = 32'd0;
//assign busre2 = 1'b0;
//assign buswe2 = 4'h0;

assign busreq[3] = 1'b0;
//assign busaddress3 = 32'd0;
//assign din3 = 32'd0;
//assign busre3 = 1'b0;
//assign buswe3 = 4'h0;

endmodule
