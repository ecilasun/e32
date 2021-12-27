`timescale 1ns / 1ps
`default_nettype none

`include "devices.vh"

module toplevel(
	input wire sys_clock,
	// UART
	output wire uart_rxd_out,
	input wire uart_txd_in,
	// SPI
	output wire spi_cs_n,
	output wire spi_mosi,
	input wire spi_miso,
	output wire spi_sck
	// TODO: DDR3
	);

// ----------------------------------------------------------------------------
// Internal wiring
// ----------------------------------------------------------------------------

// Clock/reset wires
wire wallclock, cpuclock, spibaseclock, ddr3sysclk, ddr3refclk, reset;

// Bus control wires
wire [31:0] addrs;
wire [31:0] din;
wire [31:0] dout;
wire [3:0] buswe;
wire busre;
wire [`DEVICE_COUNT-1:0] deviceSelect;

// ----------------------------------------------------------------------------
// Clock + reset generator
// ----------------------------------------------------------------------------

clockandresetgen ClockAndResetGenerator(
	.sys_clock_i(sys_clock),
	.wallclock(wallclock),
	.cpuclock(cpuclock),
	.spibaseclock(spibaseclock),
	.ddr3sysclk(ddr3sysclk),
	.ddr3refclk(ddr3refclk),
	.devicereset(reset) );

// ----------------------------------------------------------------------------
// UART
// ----------------------------------------------------------------------------

wire uartwe;
wire uartre;
wire [7:0] uartdin;
wire [7:0] uartdout;
wire uartbusy;
wire uartrcvempty;

uartdriver UARTDevice(
	.subdevice(addrs[3:0]),
	.clk10(wallclock),
	.cpuclock(cpuclock),
	.reset(reset),
	.enable(deviceSelect[`DEV_UARTANY]),
	.busy(uartbusy),
	.buswe(uartwe),
	.busre(uartre),
	.din(uartdin),
	.dout(uartdout),
	.uartrcvempty(uartrcvempty),
	.uart_rxd_out(uart_rxd_out),
	.uart_txd_in(uart_txd_in) );
	
// ----------------------------------------------------------------------------
// SPI
// ----------------------------------------------------------------------------

wire spiwe;
wire spire;
wire [7:0] spidin;
wire [7:0] spidout;
wire spibusy;

spidriver SPIDevice(
	.spibaseclock(spibaseclock),
	.cpuclock(cpuclock),
	.reset(reset),
	.enable(deviceSelect[`DEV_SPIANY]),
	.busy(spibusy),
	.buswe(spiwe),
	.busre(spire),
	.din(spidin),
	.dout(spidout),
	.spi_cs_n(spi_cs_n),
	.spi_mosi(spi_mosi),
	.spi_miso(spi_miso),
	.spi_sck(spi_sck) );

// ----------------------------------------------------------------------------
// DDR3
// ----------------------------------------------------------------------------

wire ddr3we;
wire ddr3re;
wire [31:0] ddr3din;
wire [31:0] ddr3dout;
wire ddr3busy;

ddr3driver DDR3Device(
	.ddr3sysclk(ddr3sysclk),
	.ddr3refclk(ddr3refclk),
	.cpuclock(cpuclock),
	.reset(reset),
	.enable(deviceSelect[`DEV_DDR3]),
	.busy(ddr3busy),
	.buswe(ddr3we),
	.busre(ddr3re),
	.din(ddr3din),
	.dout(ddr3dout)
	// TODO: DDR3 external wires
	);

// ----------------------------------------------------------------------------
// S-RAM (64Kbytes, also acts as boot ROM) - Scratch Memory
// It is set up as true dual port to support overlapping instruction fetch
// with data access.
// ----------------------------------------------------------------------------

// Data wires come from system bus / router
wire sramre;
wire [3:0] sramwe;
wire [31:0] sramdin;
wire [13:0] sramaddr;
wire [31:0] sramdout;

// Instruction wires go directly to memory
wire [31:0] iaddrs;
wire ire;
wire [31:0] iout;

scratchram SRAMBOOTRAMDevice(
	// Instruction port
	.clka(cpuclock),
	.addra(iaddrs[15:2]),	// instruction addresses are word aligned
	.dina(/*sramdin*/),		// no data input for now (may overlap previous STORE with next IFETCH later)
	.douta(iout),			// instruction output
	.ena(ire),				// instruction fetch enable
	.wea(4'h0),
	// Data port
	.clkb(cpuclock),
	.addrb(sramaddr),
	.dinb(sramdin),
	.doutb(sramdout),
	.enb(sramre | (|sramwe)),
	.web(sramwe) );

// ----------------------------------------------------------------------------
// System bus and attached devices
// ----------------------------------------------------------------------------

wire [3:0] irq;

sysbus SystemBus(
	.wallclock(wallclock),
	.cpuclock(cpuclock),
	.reset(reset),
	.deviceSelect(deviceSelect),
	// Bus control
	.addrs(addrs),
	.din(din),
	.dout(dout),
	.buswe(buswe),
	.busre(busre),
	// Interrupt lines
	.irq(irq),
	// UART port
	.uartwe(uartwe),
	.uartre(uartre),
	.uartdin(uartdin),
	.uartdout(uartdout),
	.uartrcvempty(uartrcvempty),
	// SPI
	.spiwe(spiwe),
	.spire(spire),
	.spidin(spidin),
	.spidout(spidout),
	// SRAM port
	.sramre(sramre),
	.sramwe(sramwe),
	.sramdin(sramdin),
	.sramaddr(sramaddr),
	.sramdout(sramdout) );

// ----------------------------------------------------------------------------
// Bus busy state
// ----------------------------------------------------------------------------

wire busbusy = ddr3busy | spibusy | uartbusy;

// ----------------------------------------------------------------------------
// CPU HART#0
// Primary CPU
// Boots the system, with reset vector set at 0x10000000
// ----------------------------------------------------------------------------

cpu #( .RESETVECTOR(32'h10000000) ) HART0
	(
	.cpuclock(cpuclock),
	.reset(reset),
	.irq(irq),
	// Instruction bus
	.iaddress(iaddrs),
	.ire(ire),
	.iin(iout),
	// Data bus
	.busaddress(addrs),
	.din(dout),
	.dout(din),
	.busre(busre),
	.buswe(buswe),
	.busbusy(busbusy) );

endmodule
