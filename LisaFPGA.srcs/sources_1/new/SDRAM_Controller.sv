`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 12/06/2025 12:02:16 PM
// Design Name: 
// Module Name: SDRAM_Controller
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module SDRAM_Controller(
    input logic clk,
    input logic [7:0] A,
    input logic [15:0] MD,
    input logic R_W,
    input logic [3:0] _CAS,
    input logic [3:0] _RAS,
    input logic _UDS,
    input logic _LDS,
    output logic [15:0] DO,
    output logic [1:0] PO,
    (*MARK_DEBUG = "TRUE" *) output logic _CE_SRAM,
    (*MARK_DEBUG = "TRUE" *) output logic _OE_SRAM,
    (*MARK_DEBUG = "TRUE" *) output logic _WE_SRAM,
    (*MARK_DEBUG = "TRUE" *) output logic _UDS_SRAM,
    (*MARK_DEBUG = "TRUE" *) output logic _LDS_SRAM,
    (*MARK_DEBUG = "TRUE" *) output logic [20:1] A_SRAM,
    (*MARK_DEBUG = "TRUE" *) input logic [15:0] DIN_SRAM,
    (*MARK_DEBUG = "TRUE" *) output logic [15:0] DOUT_SRAM,
    );

    (*MARK_DEBUG = "TRUE" *) logic [7:0] row_addr; // Latched row address (from A0-A7)
    (*MARK_DEBUG = "TRUE" *) logic [7:0] col_addr; // Latched column address (from A0-A7)

    // Latch the row address on the falling edge of _RAS
    always_ff @(negedge (&_RAS)) begin
        row_addr <= A;
    end

    // Latch the column address on the falling edge of _CAS (if RAS is already active)
    always_ff @(negedge (&_CAS)) begin
        if (!_RAS[0] | !_RAS[1] | !_RAS[2] | !_RAS[3]) // Only latch if RAS is already low
            col_addr <= A;
    end

    // The bank address is determined by which RAS/CAS pair is active; it'll be the high 2 bits of the SDRAM address
    (*MARK_DEBUG = "TRUE" *) logic [1:0] bank_addr;
    (*MARK_DEBUG = "TRUE" *) logic _CS;
    always_ff @(posedge clk) begin
        if (!_RAS[0] && !_CAS[0]) begin
            bank_addr <= 2'b00;
            _CS <= 1'b0; // Bank 0 selected
        end else if (!_RAS[1] && !_CAS[1]) begin
            bank_addr <= 2'b01;
            _CS <= 1'b0; // Bank 1 selected
        end else if (!_RAS[2] && !_CAS[2]) begin
            bank_addr <= 2'b10;
            _CS <= 1'b0; // Bank 2 selected
        end else if (!_RAS[3] && !_CAS[3]) begin
            bank_addr <= 2'b11;
            _CS <= 1'b0; // Bank 3 selected
        end else begin
            _CS <= 1'b1; // Not selected
        end
    end

    // Now let's hook all these signals up to the SDRAM chip
    assign _CE_SRAM = _CS;
    assign _OE_SRAM = ~R_W; // Output enable is low (asserted) for read operations only
    assign _WE_SRAM = R_W; // Write enable is low (asserted) for write operations only
    assign _UDS_SRAM = _UDS;
    assign _LDS_SRAM = _LDS;
    assign A_SRAM = {bank_addr, row_addr, col_addr}; // Concatenate bank, row, and column addresses to form the full SDRAM address
    assign DO = DIN_SRAM; // Data output from SDRAM, renamed for use by the rest of the system
    assign DOUT_SRAM = MD; // Data to SDRAM from controller

    // Generate parity for the low and upper bytes
    // Note that since we're doing this on the fly instead of storing parity in RAM, it doesn't support the "write wrong parity" function
    parity_generator_LS280 lower_byte_parity(
        .ABCDEFGHI({0, DO[7:0]}),
        .EVEN(PO[0]),
    );

    parity_generator_LS280 upper_byte_parity(
        .ABCDEFGHI({0, DO[15:8]}),
        .EVEN(PO[1]),
    );


endmodule
