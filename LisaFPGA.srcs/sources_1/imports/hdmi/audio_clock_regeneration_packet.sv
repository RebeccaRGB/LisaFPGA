// Implementation of HDMI audio clock regeneration packet
// By Sameer Puri https://github.com/sameer

// See HDMI 1.4b Section 5.3.3
module audio_clock_regeneration_packet
#(
    parameter int AUDIO_RATE = 48e3
)
(   
    input logic video_rate, // 1 for 1080p60, 0 for 1080p30. Moved from a parameter to an input to allow runtime changes for LisaFPGA
    input logic clk_pixel,
    input logic clk_audio,
    output logic clk_audio_counter_wrap = 0,
    output logic [23:0] header,
    output logic [55:0] sub [3:0]
);

// See Section 7.2.3, values derived from "Other" row in Tables 7-1, 7-2, 7-3.
localparam bit [19:0] N = AUDIO_RATE % 125 == 0 ? 20'(16 * AUDIO_RATE / 125) : AUDIO_RATE % 225 == 0 ? 20'(32 * AUDIO_RATE / 225) : 20'(AUDIO_RATE * 16 / 125);
// For 48KHz audio, N is 6144, so that's what we'll hard-code later on for the CYCLE_TIME_STAMP_COUNTER_IDEAL for LisaFPGA

localparam int CLK_AUDIO_COUNTER_WIDTH = $clog2(N / 128);
localparam bit [CLK_AUDIO_COUNTER_WIDTH-1:0] CLK_AUDIO_COUNTER_END = CLK_AUDIO_COUNTER_WIDTH'(N / 128 - 1);
logic [CLK_AUDIO_COUNTER_WIDTH-1:0] clk_audio_counter = CLK_AUDIO_COUNTER_WIDTH'(0);
logic internal_clk_audio_counter_wrap = 1'd0;
always_ff @(posedge clk_audio)
begin
    if (clk_audio_counter == CLK_AUDIO_COUNTER_END)
    begin
        clk_audio_counter <= CLK_AUDIO_COUNTER_WIDTH'(0);
        internal_clk_audio_counter_wrap <= !internal_clk_audio_counter_wrap;
    end
    else
        clk_audio_counter <= clk_audio_counter + 1'd1;
end

logic [1:0] clk_audio_counter_wrap_synchronizer_chain = 2'd0;
always_ff @(posedge clk_pixel)
    clk_audio_counter_wrap_synchronizer_chain <= {internal_clk_audio_counter_wrap, clk_audio_counter_wrap_synchronizer_chain[1]};

//localparam bit [19:0] CYCLE_TIME_STAMP_COUNTER_IDEAL = 20'(int'(VIDEO_RATE * int'(N) / 128 / AUDIO_RATE));
// Replace the CYCLE_TIME_STAMP_COUNTER_IDEAL localparam with a signal that can be switched between 1080p30 and 1080p60 versions on the fly
// This means we'll precalculate the result and just switch between the two precalculated values based on the video_rate signal
// Assume N=6144 and AUDIO_RATE=48000 when doing the calculation
// For 1080p30, our value is 74250, and for 1080p60, our value is 148500
/*logic [19:0] cycle_time_stamp_counter_ideal;
always_ff @(posedge clk_pixel) begin
    cycle_time_stamp_counter_ideal <= video_rate ? 20'd148500 : 20'd74250;
end*/

//localparam int CYCLE_TIME_STAMP_COUNTER_WIDTH = $clog2(20'(int'(real'(CYCLE_TIME_STAMP_COUNTER_IDEAL) * 1.1))); // Account for 10% deviation in audio clock
// Plugging in these two values for CYCLE_TIME_STAMP_COUNTER_IDEAL gives us a CYCLE_TIME_STAMP_COUNTER_WIDTH of 17 for 1080p30 and 18 for 1080p60

logic [19:0] cycle_time_stamp = 20'd0;
logic [17:0] cycle_time_stamp_counter = 18'd0;
always_ff @(posedge clk_pixel)
begin
    if (clk_audio_counter_wrap_synchronizer_chain[1] ^ clk_audio_counter_wrap_synchronizer_chain[0])
    begin
        cycle_time_stamp_counter <= 18'd0;
        cycle_time_stamp <= {2'b0, cycle_time_stamp_counter + 1};
        clk_audio_counter_wrap <= !clk_audio_counter_wrap;
    end
    else
        cycle_time_stamp_counter <= cycle_time_stamp_counter + 1;
end

// "An HDMI Sink shall ignore bytes HB1 and HB2 of the Audio Clock Regeneration Packet header."
`ifdef MODEL_TECH
assign header = {8'd0, 8'd0, 8'd1};
`else
assign header = {8'dX, 8'dX, 8'd1};
`endif

// "The four Subpackets each contain the same Audio Clock regeneration Subpacket."
genvar i;
generate
    for (i = 0; i < 4; i++)
    begin: same_packet
        assign sub[i] = {N[7:0], N[15:8], {4'd0, N[19:16]}, cycle_time_stamp[7:0], cycle_time_stamp[15:8], {4'd0, cycle_time_stamp[19:16]}, 8'd0};
    end
endgenerate

endmodule
