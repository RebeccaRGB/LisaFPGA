`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 12/04/2025 11:03:36 PM
// Design Name: 
// Module Name: sawtooth
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


module sawtooth #(
    parameter int BIT_WIDTH   = 16,
    parameter int SAMPLE_RATE = 48000,
    parameter int WAVE_RATE   = 480
)(
    input  logic clk_audio,
    output logic signed [BIT_WIDTH-1:0] level = '0
);

    // Maximum value before wrap (2^BIT_WIDTH)
    localparam int FULL_SCALE = 1 << BIT_WIDTH;

    // Compute increment using integer math with rounding
    localparam int INCREMENT =
        (WAVE_RATE * FULL_SCALE + SAMPLE_RATE/2) / SAMPLE_RATE;

    always_ff @(posedge clk_audio) begin
        level <= level + INCREMENT[BIT_WIDTH-1:0];
    end

endmodule