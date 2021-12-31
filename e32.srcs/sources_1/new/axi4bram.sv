`timescale 1ns / 1ps

module axi4bram(
    axi4 axi4if);

axi4litebmem A4LiteVRAMSinglePort(
  .s_aclk(axi4if.ACLK),            // input wire s_aclk
  .s_aresetn(axi4if.ARESETn),      // input wire s_aresetn
  .s_axi_awaddr(axi4if.AWADDR),    // input wire [31 : 0] s_axi_awaddr
  .s_axi_awvalid(axi4if.AWVALID),  // input wire s_axi_awvalid
  .s_axi_awready(axi4if.AWREADY),  // output wire s_axi_awready
  .s_axi_wdata(axi4if.WDATA),      // input wire [31 : 0] s_axi_wdata
  .s_axi_wstrb(axi4if.WSTRB),      // input wire [3 : 0] s_axi_wstrb
  .s_axi_wvalid(axi4if.WVALID),    // input wire s_axi_wvalid
  .s_axi_wready(axi4if.WREADY),    // output wire s_axi_wready
  .s_axi_bresp(axi4if.BRESP),      // output wire [1 : 0] s_axi_bresp
  .s_axi_bvalid(axi4if.BVALID),    // output wire s_axi_bvalid
  .s_axi_bready(axi4if.BREADY),    // input wire s_axi_bready
  .s_axi_araddr(axi4if.ARADDR),    // input wire [31 : 0] s_axi_araddr
  .s_axi_arvalid(axi4if.ARVALID),  // input wire s_axi_arvalid
  .s_axi_arready(axi4if.ARREADY),  // output wire s_axi_arready
  .s_axi_rdata(axi4if.RDATA),      // output wire [31 : 0] s_axi_rdata
  .s_axi_rresp(axi4if.RRESP),      // output wire [1 : 0] s_axi_rresp
  .s_axi_rvalid(axi4if.RVALID),    // output wire s_axi_rvalid
  .s_axi_rready(axi4if.RREADY)     // input wire s_axi_rready
);

endmodule
