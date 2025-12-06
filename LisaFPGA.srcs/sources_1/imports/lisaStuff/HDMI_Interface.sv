/*module HDMI_Interface(
    input  logic sysclk,
    input  logic _reset,
    input  logic DOTCK,
    input  logic _VSYNC,
    input  logic _HSYNC,
    input  logic VID,
    output logic tmds_clock,
    output logic [2:0] tmds
);

    // ----------------------------------------------------------------
    // HDMI PLL: generate pixel clocks
    // ----------------------------------------------------------------
    logic clk_pixel;
    logic clk_pixel_x5;
    logic clk_audio;

    //hdmi_pll_xilinx pll(
    //    .clk_in1(sysclk),
    //    .clk_out1(clk_pixel),
    //    .clk_out2(clk_pixel_x5)
    //);

    HDMI_MMCM_Mode2_59Hz hdmi_clockgen (
        .sysclk(sysclk),
        .clk_pixel(clk_pixel),
        .clk_pixel_x5(clk_pixel_x5)
    );

    //HDMI_MMCM_Mode34_30Hz hdmi_clockgen (
    //    .sysclk(sysclk),
    //    .clk_pixel(clk_pixel),
    //    .clk_pixel_x5(clk_pixel_x5)
    //);

    // Dummy audio
    logic [10:0] counter = 1'd0;
    always_ff @(posedge clk_pixel) begin
        counter <= counter == 11'd1546 ? 1'd0 : counter + 1'd1;
    end
    assign clk_audio = clk_pixel && (counter == 11'd1546);

    logic [15:0] audio_sample_word [1:0];
    assign audio_sample_word = '{16'd0, 16'd0}; // silence

    // ----------------------------------------------------------------
    // Framebuffer (double-buffered)
    // ----------------------------------------------------------------
    // Each buffer: 32K bytes = Lisa’s 720*364/8 = ~32K
    logic [7:0] buf0 [0:32759];
    logic [7:0] buf1 [0:32759];

    (* MARK_DEBUG = "TRUE" *) logic active_buf;     // 0 = buf0 is displayed, 1 = buf1 is displayed
    (* MARK_DEBUG = "TRUE" *) logic write_buf_sel;  // opposite of active_buf
    (* MARK_DEBUG = "TRUE" *) logic swap_request;   // handshake for VSYNC swap

    // ----------------------------------------------------------------
    // Video capture domain (DOTCK, negedge)
    // ----------------------------------------------------------------
    (* MARK_DEBUG = "TRUE" *) logic [14:0] byte_counter;
    (* MARK_DEBUG = "TRUE" *) logic [2:0]  bit_counter;
    (* MARK_DEBUG = "TRUE" *) logic [7:0]  current_byte;

    always_ff @(negedge DOTCK) begin
        if (!_reset) begin
            bit_counter  <= 0;
            byte_counter <= 0;
            current_byte <= 8'd0;
            swap_request <= 0;
        end else begin
            if (_VSYNC == 1'b0) begin
                // VSYNC low: restart and request buffer swap
                bit_counter  <= 0;
                byte_counter <= 0;
                current_byte <= 8'd0;
                swap_request <= 1;
            end else if (_HSYNC == 1'b0) begin
                swap_request <= 0;
                // Active video region
                current_byte <= {current_byte[6:0], VID};
                if (bit_counter == 3'd7) begin
                    if (write_buf_sel == 1'b0)
                        buf0[byte_counter] <= {current_byte[6:0], VID};
                    else
                        buf1[byte_counter] <= {current_byte[6:0], VID};

                    byte_counter <= byte_counter + 1;
                    bit_counter  <= 0;
                    current_byte <= 0;
                end else begin
                    bit_counter <= bit_counter + 1;
                end
            end else begin
                swap_request <= 0;
                // hblank, still advance bits (just like active branch above?)
                if (bit_counter == 3'd7) begin
                    if (write_buf_sel == 1'b0)
                        buf0[byte_counter] <= {current_byte[6:0], VID};
                    else
                        buf1[byte_counter] <= {current_byte[6:0], VID};

                    byte_counter <= byte_counter + 1;
                    bit_counter  <= 0;
                    current_byte <= 0;
                end
            end
        end
    end

    // ----------------------------------------------------------------
    // Buffer swap synchronizer (DOTCK → clk_pixel)
    // -------------------------------------MARK_DEBUG---------------------------------
    (* MARK_DEBUG = "TRUE" *) logic swap_request_sync1, swap_request_sync2;
    always_ff @(posedge clk_pixel) begin
        if (!_reset) begin
            active_buf    <= 1'b0;
            write_buf_sel <= 1'b1;
            swap_request_sync1 <= 1'b0;
            swap_request_sync2 <= 1'b0;
        end
        swap_request_sync1 <= swap_request;
        swap_request_sync2 <= swap_request_sync1;
        if (swap_request_sync1 && !swap_request_sync2) begin
            // swap buffers
            active_buf    <= ~active_buf;
            write_buf_sel <= active_buf; // opposite
        end
    end

    // ----------------------------------------------------------------
    // HDMI readout (clk_pixel domain)
    // ----------------------------------------------------------------
    (* MARK_DEBUG = "TRUE" *) logic [23:0] rgb;
    (* MARK_DEBUG = "TRUE" *) logic [11:0] cx;
    (* MARK_DEBUG = "TRUE" *) logic [10:0] cy;

    //(* MARK_DEBUG = "TRUE" *) logic [9:0] lisa_x, lisa_y;
    (* MARK_DEBUG = "TRUE" *) logic [18:0] fb_index;
    (* MARK_DEBUG = "TRUE" *) logic [14:0] word_index;
    (* MARK_DEBUG = "TRUE" *) logic [2:0]  bit_index;
    (* MARK_DEBUG = "TRUE" *) logic pixel;

    always_comb begin
        // Scale mapping: 1920x1080 -> 720x364 doubled/tripled
        //lisa_x     = (cx - 240) >> 1;  // 0–719
        //lisa_y     = cy / 3;           // 0–363
        //fb_index   = lisa_y * 720 + lisa_x; // 0..262143
        //word_index = fb_index >> 3;
        //bit_index  = fb_index & 7;
        fb_index = (cy * 720) + cx;
        word_index = fb_index >> 3;
        bit_index  = fb_index & 7;

        if (active_buf == 1'b0)
            pixel = buf0[word_index][bit_index];
        else
            pixel = buf1[word_index][bit_index];
    end

    always_ff @(posedge clk_pixel) begin
        //if (cx >= 240 && cx < 1680 && cy < 1092) begin
        if (cy < 364) begin
            rgb <= pixel ? 24'h000000 : 24'hFFFFFF;
        end else begin
            rgb <= 24'h202020; // border
        end
    end

    // ----------------------------------------------------------------
    // HDMI IP Core
    // ----------------------------------------------------------------
    hdmi #(
        .VIDEO_ID_CODE(2), //2
        .VIDEO_REFRESH_RATE(59.94), //59.94
        .AUDIO_RATE(48000),
        .AUDIO_BIT_WIDTH(16)
    ) hdmi_inst (
        .clk_pixel_x5(clk_pixel_x5),
        .clk_pixel(clk_pixel),
        .clk_audio(clk_audio),
        .reset(~_reset),
        .rgb(rgb),
        .audio_sample_word(audio_sample_word),
        .tmds(tmds),
        .tmds_clock(tmds_clock),
        .cx(cx),
        .cy(cy)
    );

endmodule*/



`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 09/20/2025 01:23:33 AM
// Design Name: 
// Module Name: HDMI_Interface
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


module HDMI_Interface(
    input logic sysclk,
    input logic _reset,
    input logic DOTCK,
    input logic VA_overflow, // Replaces VSYNC; active high during vertical blanking
    input logic _clr_vid_clk, // Replaces _HSYNC; active low during horizontal blanking
    input logic VID,
    input logic [5:0] CONT,
    input logic INVID,
    input logic TONE,
    input logic [2:0] VC,
    output logic tmds_clock,
    output logic [2:0] tmds
    );
 
    logic clk_pixel;
    logic clk_pixel_x5;
    logic clk_audio;

    hdmi_pll_xilinx pll(.clk_in1(sysclk), .clk_out1(clk_pixel), .clk_out2(clk_pixel_x5));

    /*HDMI_MMCM_Mode16_60Hz hdmi_clockgen (
        .sysclk(sysclk),
        .clk_pixel(clk_pixel),
        .clk_pixel_x5(clk_pixel_x5)
    );*/

    logic [10:0] counter = 1'd0;
    always_ff @(posedge clk_pixel)
    begin
        counter <= counter == 11'd1546 ? 1'd0 : counter + 1'd1;
    end
    assign clk_audio = clk_pixel && counter == 11'd1546;

    (* MARK_DEBUG = "TRUE" *) logic [15:0] audio_sample_word;

    // Now let's do the audio sample generation
    // We take our input audio square wave on TONE and volume on VC (3 bits)
    // And then we convert it to two 16-bit audio samples (stereo)
    // Both channels will be the same since the Lisa is mono
    // We need to convert the square wave to a PCM value, and scale it linearly based on VC
    // VC = 000 = mute, VC = 111 = max volume
    // So when TONE is high, output max_volume, when TONE is low, output 0
    // max_volume = (VC / 7) * 65535
    // So final output = TONE ? max_volume : 0
    logic [15:0] max_volume;
    assign max_volume = (VC == 3'd0) ? 16'd0 :
                        (VC == 3'd1) ? 16'd9362 :
                        (VC == 3'd2) ? 16'd18724 :
                        (VC == 3'd3) ? 16'd28086 :
                        (VC == 3'd4) ? 16'd37448 :
                        (VC == 3'd5) ? 16'd46810 :
                        (VC == 3'd6) ? 16'd56172 :
                                       16'd65535;
    always_ff @(posedge clk_audio) begin
        audio_sample_word <= TONE ? max_volume : 0; //-max_volume;
    end

    logic [23:0] rgb = 24'd0;
    (* MARK_DEBUG = "TRUE" *) logic [11:0] cx;
    (* MARK_DEBUG = "TRUE" *) logic [10:0] cy;

    // We'll use the full vertical resolution (actually a little more), and less of the horizontal resolution
    // The Lisa is 720x364, so we'll center that in 1920x1080, but each Lisa pixel is 3 pixels high and 2 pixels wide
    // So we'll actually use 1440x1092 (720*2 x 364*3) centered in 1920x1080
    // This gives us a border of 240 pixels on the left and right, and we'll just crop 12 pixels off the bottom
    // The Lisa framebuffer is a 32K 1 bit per pixel bitmap
    logic [7:0] lisa_framebuffer [0:32759];
    (* MARK_DEBUG = "TRUE" *) logic [9:0] lisa_x, lisa_y;
    (* MARK_DEBUG = "TRUE" *) logic [18:0] fb_index;
    (* MARK_DEBUG = "TRUE" *) logic [14:0] word_index;
    (* MARK_DEBUG = "TRUE" *) logic [2:0] bit_index;
    (* MARK_DEBUG = "TRUE" *) logic pixel;
    // Missing one single column of pixels on tghe right of the frame
    // Left side of the frame has 3? (maybe 2 maybe 4) extra columns of black pixels
    (* MARK_DEBUG = "TRUE" *) logic [14:0] byte_counter;
    (* MARK_DEBUG = "TRUE" *) logic [2:0] bit_counter;
    (* MARK_DEBUG = "TRUE" *) logic [7:0] current_byte;
    (* MARK_DEBUG = "TRUE" *) logic [2:0] end_line_overlap_counter;
    (* MARK_DEBUG = "TRUE" *) logic [2:0] start_line_overlap_counter;
    (* MARK_DEBUG = "TRUE" *) logic [1:0] hsync_delay_counter;
    (* MARK_DEBUG = "TRUE" *) logic prev_clr_vid_clk;
    always_ff @(negedge DOTCK) begin
        prev_clr_vid_clk <= _clr_vid_clk;
        if (!_reset) begin
            bit_counter <= 0;
            byte_counter <= 0;
            current_byte <= 8'd0;
            start_line_overlap_counter <= 0;
            end_line_overlap_counter <= 0;
            hsync_delay_counter <= 0;
        end else begin
            if (VA_overflow == 1'b1) begin
                bit_counter <= 0;
                byte_counter <= 0;
                current_byte <= 8'd0;
                hsync_delay_counter <= 0;
            end else if ((_clr_vid_clk == 1'b1 || end_line_overlap_counter != 3'd7) && hsync_delay_counter == 2'd2) begin
                if (_clr_vid_clk == 1'b0 && end_line_overlap_counter != 3'd7) begin
                    end_line_overlap_counter <= end_line_overlap_counter + 1;
                end else if (_clr_vid_clk == 1'b1) begin
                    end_line_overlap_counter <= 3'd0;
                end
                if (start_line_overlap_counter != 3'd7) begin
                    start_line_overlap_counter <= start_line_overlap_counter + 1;
                end else begin
                    if (bit_counter == 3'd7) begin
                        lisa_framebuffer[byte_counter] <= {VID, current_byte[7:1]};
                        byte_counter <= byte_counter + 1;
                        bit_counter <= 0;
                        current_byte <= 8'd0;
                    end else begin
                        current_byte <= {VID, current_byte[7:1]};
                        bit_counter <= bit_counter + 1;
                    end
                end
            end else begin
                start_line_overlap_counter <= 3'd0;
                if (hsync_delay_counter != 2'd2 && prev_clr_vid_clk && !_clr_vid_clk) begin
                    hsync_delay_counter <= hsync_delay_counter + 1;
                end
                if (bit_counter == 3'd7) begin
                    lisa_framebuffer[byte_counter] <= {VID, current_byte[7:1]};
                    byte_counter <= byte_counter + 1;
                    bit_counter <= 0;
                    current_byte <= 8'd0;
                end
            end
        end
    end

    always_comb begin
        // Map (cx, cy) to (lx, ly) in Lisa coordinates
        lisa_x = (cx - 240) >> 1; // Divide by 2, gives us Lisa pixel x coordinate 0-719
        lisa_y = cy / 3; // Divide by 3, gives us Lisa pixel y coordinate 0-363
        fb_index   = lisa_y * 720 + lisa_x;   // 0..262143
        word_index = fb_index >> 3;           // divide by 8
        bit_index  = fb_index & 7;            // which bit inside the byte
        pixel = lisa_framebuffer[word_index][bit_index];
    end

    always @(posedge clk_pixel) begin
        if (cx >= 240 && cx < 1680 && cy < 1092) begin
            // Inside the active area
            // Figure out if the pixel is black or white, taking INVID and CONT into account
            rgb <= (pixel ^ INVID) ? 24'h000000 : {(6'h3f - CONT), 2'b00, (6'h3f - CONT), 2'b00, (6'h3f - CONT), 2'b00};
        end else begin
            rgb <= 24'h202020;
        end
    end

    // 1920x1080 @ 60Hz
    hdmi #(.VIDEO_ID_CODE(16), .VIDEO_REFRESH_RATE(60.0), .AUDIO_RATE(48000), .AUDIO_BIT_WIDTH(16)) hdmi(
        .clk_pixel_x5(clk_pixel_x5), // Input clocks
        .clk_pixel(clk_pixel),
        .clk_audio(clk_audio),
        .reset(~_reset), // Reset switch, active high
        .rgb(rgb), // RGB pixel value
        .audio_sample_word({audio_sample_word, audio_sample_word}), // Audio sample, ignore for now
        .tmds(tmds), // outputs to HDMI port
        .tmds_clock(tmds_clock),
        .cx(cx), // x and y coordinates of current pixel
        .cy(cy)
    );

endmodule