`timescale 1ns / 1ps

module axi4chain(
	axi4 axi4if,
	// IRQ
	output wire [3:0] irq,
	// UART
	input uartbaseclock,
	output wire uart_rxd_out,
	input wire uart_txd_in,
	// SPI
	input spibaseclock,
	output wire spi_cs_n,
	output wire spi_mosi,
	input wire spi_miso,
	output wire spi_sck,
	// DDR3
	input wire clk_sys_i,
	input wire clk_ref_i,
    output wire [13:0] ddr3_addr,
    output wire [2:0] ddr3_ba,
    output wire ddr3_cas_n,
    output wire [0:0] ddr3_ck_n,
    output wire [0:0] ddr3_ck_p,
    output wire [0:0] ddr3_cke,
    output wire ddr3_ras_n,
    output wire ddr3_reset_n,
    output wire ddr3_we_n,
    inout wire [15:0] ddr3_dq,
    inout wire [1:0] ddr3_dqs_n,
    inout wire [1:0] ddr3_dqs_p,
	output wire [0:0] ddr3_cs_n,
    output wire [1:0] ddr3_dm,
    output wire [0:0] ddr3_odt );

logic [1:0] waddrstate = 2'b00;
logic [1:0] writestate = 2'b00;
logic [1:0] raddrstate = 2'b00;

logic [31:0] writeaddress = 32'd0;
logic [31:0] readaddress = 32'd0;
logic [31:0] writedata = 32'd0;
wire [31:0] readdata;
logic [3:0] we = 4'h0;
logic re = 1'b0;

// S-RAM (scratchpad) @A0000000-A0003FFF
wire validwaddr_sram = ~(|(4'hA ^ axi4if.AWADDR[31:28]));
wire validraddr_sram = ~(|(4'hA ^ axi4if.ARADDR[31:28]));
axi4 sramif(axi4if.ACLK, axi4if.ARESETn);
axi4sram SRAM(
	.axi4if(sramif.SLAVE));

// UART @80000000-80000008
wire validwaddr_uart = ~(|(4'h8 ^ axi4if.AWADDR[31:28]));
wire validraddr_uart = ~(|(4'h8 ^ axi4if.ARADDR[31:28]));
axi4 uartif(axi4if.ACLK, axi4if.ARESETn);
wire uartrcvempty;
axi4uart UART(
	.axi4if(uartif.SLAVE),
	.uartrcvempty(uartrcvempty),
	.uartbaseclock(uartbaseclock),
	.uart_rxd_out(uart_rxd_out),
	.uart_txd_in(uart_txd_in) );

// SPIMaster @90000000-90000000
wire validwaddr_spi = ~(|(4'h9 ^ axi4if.AWADDR[31:28]));
wire validraddr_spi = ~(|(4'h9 ^ axi4if.ARADDR[31:28]));
axi4 spiif(axi4if.ACLK, axi4if.ARESETn);
axi4spi SPIMaster(
	.axi4if(spiif.SLAVE),
	.spibaseclock(spibaseclock),
	.spi_cs_n(spi_cs_n),
	.spi_mosi(spi_mosi),
	.spi_miso(spi_miso),
	.spi_sck(spi_sck) );

// B-RAM (boot program memory ram) @10000000-1000FFFF
wire validwaddr_bram = ~(|(4'h1 ^ axi4if.AWADDR[31:28]));
wire validraddr_bram = ~(|(4'h1 ^ axi4if.ARADDR[31:28]));
axi4 bramif(axi4if.ACLK, axi4if.ARESETn);
axi4bram BRAM(
	.axi4if(bramif.SLAVE));

// DDR3 @00000000-0FFFFFFF
wire validwaddr_ddr3 = 4'h0 == axi4if.AWADDR[31:28];
wire validraddr_ddr3 = 4'h0 == axi4if.ARADDR[31:28];
axi4 ddr3if(axi4if.ACLK, axi4if.ARESETn);
axi4ddr3 DDR3RAM(
	.axi4if(ddr3if.SLAVE),
	.enable(validwaddr_ddr3 | validraddr_ddr3),
	.clk_sys_i(clk_sys_i),
	.clk_ref_i(clk_ref_i),
    .ddr3_addr(ddr3_addr),
    .ddr3_ba(ddr3_ba),
    .ddr3_cas_n(ddr3_cas_n),
    .ddr3_ck_n(ddr3_ck_n),
    .ddr3_ck_p(ddr3_ck_p),
    .ddr3_cke(ddr3_cke),
    .ddr3_ras_n(ddr3_ras_n),
    .ddr3_reset_n(ddr3_reset_n),
    .ddr3_we_n(ddr3_we_n),
    .ddr3_dq(ddr3_dq),
    .ddr3_dqs_n(ddr3_dqs_n),
    .ddr3_dqs_p(ddr3_dqs_p),
	.ddr3_cs_n(ddr3_cs_n),
    .ddr3_dm(ddr3_dm),
    .ddr3_odt(ddr3_odt) );

// NULL device active when no valid addres range is selected
wire validwaddr_none = ~(validwaddr_sram | validwaddr_uart | validwaddr_spi | validwaddr_bram | validwaddr_ddr3);
wire validraddr_none = ~(validraddr_sram | validraddr_uart | validraddr_spi | validraddr_bram | validraddr_ddr3);

// Device interrupt requests
assign irq = {3'b000, ~uartrcvempty};

// Dummy device that will noop writes, and return FFFFFFFF on reads.
axi4 dummyif(axi4if.ACLK, axi4if.ARESETn);
axi4dummy NULLDEVICE(
	.axi4if(dummyif.SLAVE) );

// Mirror write channels
always_comb begin
	uartif.AWADDR = validwaddr_uart ? {4'h0,axi4if.AWADDR[27:0]} : 32'dz;
	uartif.AWVALID = validwaddr_uart ? axi4if.AWVALID : 1'b0;
	uartif.WDATA = validwaddr_uart ? axi4if.WDATA : 32'dz;
	uartif.WSTRB = validwaddr_uart ? axi4if.WSTRB : 4'h0;
	uartif.WVALID = validwaddr_uart ? axi4if.WVALID : 1'b0;
	uartif.BREADY = validwaddr_uart ? axi4if.BREADY : 1'b0;

	sramif.AWADDR = validwaddr_sram ? {4'h0,axi4if.AWADDR[27:0]} : 32'dz;
	sramif.AWVALID = validwaddr_sram ? axi4if.AWVALID : 1'b0;
	sramif.WDATA = validwaddr_sram ? axi4if.WDATA : 32'dz;
	sramif.WSTRB = validwaddr_sram ? axi4if.WSTRB : 4'h0;
	sramif.WVALID = validwaddr_sram ? axi4if.WVALID : 1'b0;
	sramif.BREADY = validwaddr_sram ? axi4if.BREADY : 1'b0;

	spiif.AWADDR = validwaddr_spi ? {4'h0,axi4if.AWADDR[27:0]} : 32'dz;
	spiif.AWVALID = validwaddr_spi ? axi4if.AWVALID : 1'b0;
	spiif.WDATA = validwaddr_spi ? axi4if.WDATA : 32'dz;
	spiif.WSTRB = validwaddr_spi ? axi4if.WSTRB : 4'h0;
	spiif.WVALID = validwaddr_spi ? axi4if.WVALID : 1'b0;
	spiif.BREADY = validwaddr_spi ? axi4if.BREADY : 1'b0;

	bramif.AWADDR = validwaddr_bram ? {4'h0,axi4if.AWADDR[27:0]} : 32'dz;
	bramif.AWVALID = validwaddr_bram ? axi4if.AWVALID : 1'b0;
	bramif.WDATA = validwaddr_bram ? axi4if.WDATA : 32'dz;
	bramif.WSTRB = validwaddr_bram ? axi4if.WSTRB : 4'h0;
	bramif.WVALID = validwaddr_bram ? axi4if.WVALID : 1'b0;
	bramif.BREADY = validwaddr_bram ? axi4if.BREADY : 1'b0;

	ddr3if.AWADDR = validwaddr_ddr3 ? {4'h0,axi4if.AWADDR[27:0]} : 32'dz;
	ddr3if.AWVALID = validwaddr_ddr3 ? axi4if.AWVALID : 1'b0;
	ddr3if.WDATA = validwaddr_ddr3 ? axi4if.WDATA : 32'dz;
	ddr3if.WSTRB = validwaddr_ddr3 ? axi4if.WSTRB : 4'h0;
	ddr3if.WVALID = validwaddr_ddr3 ? axi4if.WVALID : 1'b0;
	ddr3if.BREADY = validwaddr_ddr3 ? axi4if.BREADY : 1'b0;

	dummyif.AWADDR = validwaddr_none ? {4'h0,axi4if.AWADDR[27:0]} : 32'dz;
	dummyif.AWVALID = validwaddr_none ? axi4if.AWVALID : 1'b0;
	dummyif.WDATA = validwaddr_none ? axi4if.WDATA : 32'dz;
	dummyif.WSTRB = validwaddr_none ? axi4if.WSTRB : 4'h0;
	dummyif.WVALID = validwaddr_none ? axi4if.WVALID : 1'b0;
	dummyif.BREADY = validwaddr_none ? axi4if.BREADY : 1'b0;

	if (validwaddr_uart) begin
		axi4if.AWREADY = uartif.AWREADY;
		axi4if.BRESP = uartif.BRESP;
		axi4if.BVALID = uartif.BVALID;
		axi4if.WREADY = uartif.WREADY;
	end else if (validwaddr_sram) begin
		axi4if.AWREADY = sramif.AWREADY;
		axi4if.BRESP = sramif.BRESP;
		axi4if.BVALID = sramif.BVALID;
		axi4if.WREADY = sramif.WREADY;
	end else if (validwaddr_spi) begin
		axi4if.AWREADY = spiif.AWREADY;
		axi4if.BRESP = spiif.BRESP;
		axi4if.BVALID = spiif.BVALID;
		axi4if.WREADY = spiif.WREADY;
	end else if (validwaddr_bram) begin
		axi4if.AWREADY = bramif.AWREADY;
		axi4if.BRESP = bramif.BRESP;
		axi4if.BVALID = bramif.BVALID;
		axi4if.WREADY = bramif.WREADY;
	end else if (validwaddr_ddr3) begin
		axi4if.AWREADY = ddr3if.AWREADY;
		axi4if.BRESP = ddr3if.BRESP;
		axi4if.BVALID = ddr3if.BVALID;
		axi4if.WREADY = ddr3if.WREADY;
	end else begin
		axi4if.AWREADY = dummyif.AWREADY;
		axi4if.BRESP = dummyif.BRESP;
		axi4if.BVALID = dummyif.BVALID;
		axi4if.WREADY = dummyif.WREADY;
	end
end

// Mirror read channels
always_comb begin

	uartif.ARADDR = validraddr_uart ? {4'h0,axi4if.ARADDR[27:0]} :32'dz;
	uartif.ARVALID = validraddr_uart ? axi4if.ARVALID : 1'b0;
	uartif.RREADY = validraddr_uart ? axi4if.RREADY : 1'b0;

	sramif.ARADDR = validraddr_sram ? {4'h0,axi4if.ARADDR[27:0]} :32'dz;
	sramif.ARVALID = validraddr_sram ? axi4if.ARVALID : 1'b0;
	sramif.RREADY = validraddr_sram ? axi4if.RREADY : 1'b0;

	spiif.ARADDR = validraddr_spi ? {4'h0,axi4if.ARADDR[27:0]} :32'dz;
	spiif.ARVALID = validraddr_spi ? axi4if.ARVALID : 1'b0;
	spiif.RREADY = validraddr_spi ? axi4if.RREADY : 1'b0;

	bramif.ARADDR = validraddr_bram ? {4'h0,axi4if.ARADDR[27:0]} :32'dz;
	bramif.ARVALID = validraddr_bram ? axi4if.ARVALID : 1'b0;
	bramif.RREADY = validraddr_bram ? axi4if.RREADY : 1'b0;

	ddr3if.ARADDR = validraddr_ddr3 ? {4'h0,axi4if.ARADDR[27:0]} :32'dz;
	ddr3if.ARVALID = validraddr_ddr3 ? axi4if.ARVALID : 1'b0;
	ddr3if.RREADY = validraddr_ddr3 ? axi4if.RREADY : 1'b0;

	dummyif.ARADDR = validraddr_none ? {4'h0,axi4if.ARADDR[27:0]} :32'dz;
	dummyif.ARVALID = validraddr_none ? axi4if.ARVALID : 1'b0;
	dummyif.RREADY = validraddr_none ? axi4if.RREADY : 1'b0;

	if (validraddr_uart) begin
		axi4if.ARREADY = uartif.ARREADY;
		axi4if.RDATA = uartif.RDATA;
		axi4if.RRESP = uartif.RRESP;
		axi4if.RVALID = uartif.RVALID;
	end else if (validraddr_sram) begin
		axi4if.ARREADY = sramif.ARREADY;
		axi4if.RDATA = sramif.RDATA;
		axi4if.RRESP = sramif.RRESP;
		axi4if.RVALID = sramif.RVALID;
	end else if (validraddr_spi) begin
		axi4if.ARREADY = spiif.ARREADY;
		axi4if.RDATA = spiif.RDATA;
		axi4if.RRESP = spiif.RRESP;
		axi4if.RVALID = spiif.RVALID;
	end else if (validraddr_bram) begin
		axi4if.ARREADY = bramif.ARREADY;
		axi4if.RDATA = bramif.RDATA;
		axi4if.RRESP = bramif.RRESP;
		axi4if.RVALID = bramif.RVALID;
	end else if (validraddr_ddr3) begin
		axi4if.ARREADY = ddr3if.ARREADY;
		axi4if.RDATA = ddr3if.RDATA;
		axi4if.RRESP = ddr3if.RRESP;
		axi4if.RVALID = ddr3if.RVALID;
	end else begin
		axi4if.ARREADY = dummyif.ARREADY;
		axi4if.RDATA = dummyif.RDATA;
		axi4if.RRESP = dummyif.RRESP;
		axi4if.RVALID = dummyif.RVALID;
	end
end

endmodule
