`include "devices.vh"

module sysbus(
	// Module control
	input wire wallclock,
	input wire cpuclock,
	input wire reset,
	output wire [`DEVICE_COUNT-1:0] deviceSelect,
	// UART
	output wire uart_rxd_out,
	input wire uart_txd_in,
	// Interrupts
	output wire irqtrigger,
	output wire [3:0] irqlines,
	// Bus access
	input wire [3:0] busreq,
	output wire [3:0] busgnt,
	// Bus control
	input wire [31:0] busaddress,
	input wire [31:0] din,
	output logic [31:0] dout = 32'd0,
	input wire [3:0] buswe,
	input wire busre,
	output wire busbusy,
	// UART port
	output wire uartwe,
	output wire uartre,
	output wire [31:0] uartdin,
	input wire [31:0] uartdout,
	input wire uartbusy,
	input wire uartrcvempty,
	// SRAM port
	output wire sramre,
	output wire [3:0] sramwe,
	output wire [31:0] sramdin,
	output wire [13:0] sramaddr,
	input wire [31:0] sramdout );

// ----------------------------------------------------------------------------
// Arbiter
// ----------------------------------------------------------------------------

arbiter BusArbiter(
  .clk(cpuclock),
  .rst(reset),
  .req3(busreq[3]),
  .req2(busreq[2]),
  .req1(busreq[1]),
  .req0(busreq[0]),
  .gnt3(busgnt[3]),
  .gnt2(busgnt[2]),
  .gnt1(busgnt[1]),
  .gnt0(busgnt[0]) );

// ----------------------------------------------------------------------------
// Bus latch
// ----------------------------------------------------------------------------

bit [31:0] addrs = 32'd0;

// Adhere to new address if buswe or busre are enabled
always_comb begin
	if ((|buswe) | busre) begin
		addrs = busaddress;
	end
end

// ----------------------------------------------------------------------------
// Memory mapped device select line
// ----------------------------------------------------------------------------

assign deviceSelect = {
	{addrs[31:28], addrs[5:2]} == 8'b1000_0011 ? 1'b1 : 1'b0,	// 06: 0x8xxxxx0C SPI read/write port					+DEV_SPIRW
	{addrs[31:28], addrs[5:2]} == 8'b1000_0010 ? 1'b1 : 1'b0,	// 05: 0x8xxxxx08 UART read/write port					+DEV_UARTRW
	{addrs[31:28], addrs[5:2]} == 8'b1000_0001 ? 1'b1 : 1'b0,	// 04: 0x8xxxxx04 UART incoming queue byte available	+DEV_UARTBYTEAVAILABLE
	{addrs[31:28], addrs[5:2]} == 8'b1000_0000 ? 1'b1 : 1'b0,	// 03: 0x8xxxxx00 UART outgoing queue full				+DEV_UARTSENDFIFOFULL
	(addrs[31:28]==4'b0011) ? 1'b1 : 1'b0,						// 02: 0x30000000 - 0x30010000 - P-RAM (64Kbytes)		+DEV_PRAM
	(addrs[31:28]==4'b0010) ? 1'b1 : 1'b0,						// 02: 0x20000000 - 0x20010000 - G-RAM (64Kbytes)		+DEV_GRAM
	(addrs[31:28]==4'b0001) ? 1'b1 : 1'b0,						// 01: 0x10000000 - 0x10010000 - S-RAM (64Kbytes)		+DEV_SRAM
	(addrs[31:28]==4'b0000) ? 1'b1 : 1'b0						// 00: 0x00000000 - 0x0FFFFFFF - DDR3 (256Mbytes)		+DEV_DDR3
};

// ----------------------------------------------------------------------------
// UART control
// ----------------------------------------------------------------------------

// Single byte write, therefore we collapse buswe into 1 bit via wide OR
assign uartwe = deviceSelect[`DEV_UARTRW] ? (|buswe) : 1'b0;
// Read from either incoming data port, byte available port or send fifo full port
assign uartre = (deviceSelect[`DEV_UARTRW] | deviceSelect[`DEV_UARTBYTEAVAILABLE] | deviceSelect[`DEV_UARTSENDFIFOFULL]) ? busre : 1'b0;
// Data to UART
assign uartdin = deviceSelect[`DEV_UARTRW] ? din : 32'd0;

// ----------------------------------------------------------------------------
// S-RAM control
// ----------------------------------------------------------------------------

assign sramre = deviceSelect[`DEV_SRAM] ? busre : 1'b0;
assign sramwe = deviceSelect[`DEV_SRAM] ? buswe : 4'h0;
assign sramdin = deviceSelect[`DEV_SRAM] ? din : 32'd0;
assign sramaddr = deviceSelect[`DEV_SRAM] ? addrs[15:2] : 0;

// ----------------------------------------------------------------------------
// External interrupts
// ----------------------------------------------------------------------------

// TODO: Generate interrupt bits for more devices
// Currently UART will keep triggerring an interrupt when FIFO has anything in it until it's completely drained
// NOTE: As we're servicing interrupts, further interrupts are disabled so it's not an issue to have IRQ high at all times
assign irqlines = {3'b000, ~uartrcvempty};
// Wide-OR to trigger when any interrupt is high.
// NOTE: Watch out for incoming clock domains here; irqtrigger is used by cpuclock domain!
assign irqtrigger = |irqlines;

// ----------------------------------------------------------------------------
// Read data select
// ----------------------------------------------------------------------------

// Based on device, set the incoming data for CPU reads.
always_comb begin
	case (1'b1)
		deviceSelect[`DEV_SRAM]:					dout = sramdout;		// Read from S-RAM
		deviceSelect[`DEV_UARTRW],
		deviceSelect[`DEV_UARTBYTEAVAILABLE],
		deviceSelect[`DEV_UARTSENDFIFOFULL]:		dout = uartdout;		// Read from UART_data or UART_status
	endcase
end

// Busy is high when bus is not able to respond to requests just yet
assign busbusy = (uartbusy);// | (deviceSelect[somedevice]&(rbusy|wbusy)) | (...)

endmodule
