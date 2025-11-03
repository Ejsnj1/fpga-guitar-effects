module guitar_system_top (
    input wire i_mck,
    input wire i_bck, 
    input wire i_lrck,
    input wire i_data,
    output wire o_bck,
    output wire o_lrck,
    output wire o_data,
    input wire effect_enable
);

// 时钟直接透传
assign o_bck = i_bck;
assign o_lrck = i_lrck;

// === I2S接收器 ===
wire [23:0] left_data, right_data;
wire data_valid;
wire current_channel;
wire [4:0] bck_counter;

proper_i2s_receiver receiver (
    .i_bck(i_bck),
    .i_lrck(i_lrck), 
    .i_data(i_data),
    .o_left_data(left_data),
    .o_right_data(right_data),
    .o_data_valid(data_valid),
    .current_channel(current_channel),
    .debug_bck_counter(bck_counter)
);

// === 失真效果处理 ===
wire [23:0] distorted_signal;
wire [23:0] processed_left, processed_right;

// 实例化失真模块
simple_distortion dist_effect (
    .clk(i_bck),
    .sample_in(left_data),
    .sample_out(distorted_signal)
);

// === 单声道转立体声 + 效果选择 ===
assign processed_left = effect_enable ? distorted_signal : left_data;
assign processed_right = effect_enable ? distorted_signal : left_data;

// === I2S发送器 ===
parallel_to_i2s transmitter (
    .i_bck(i_bck),
    .i_lrck(i_lrck),
    .i_left_data(processed_left),
    .i_right_data(processed_right), 
    .o_serial_data(o_data)
);

endmodule

// ==================== 简单失真效果模块 ====================
module simple_distortion (
    input wire clk,
    input wire signed [23:0] sample_in,
    output reg signed [23:0] sample_out
);

// 失真参数 - 经典摇滚风格
localparam signed [15:0] GAIN = 16'h0200;      // 2.0倍增益
localparam signed [23:0] CLIP_LEVEL = 24'h300000; // 削波电平

// 内部信号
wire signed [39:0] mult_result;
reg signed [23:0] amplified;

// 1. 增益放大
assign mult_result = sample_in * GAIN;
assign amplified = mult_result[31:8];  // 右移8位

// 2. 软削波处理
always @(posedge clk) begin
    if (amplified > CLIP_LEVEL) begin
        sample_out <= CLIP_LEVEL;
    end else if (amplified < -CLIP_LEVEL) begin
        sample_out <= -CLIP_LEVEL;
    end else begin
        sample_out <= amplified;
    end
end

endmodule

// ==================== I2S接收器 ====================
module proper_i2s_receiver (
    input wire i_bck,
    input wire i_lrck, 
    input wire i_data,
    output reg [23:0] o_left_data,
    output reg [23:0] o_right_data,
    output reg o_data_valid,
    output reg current_channel,
    output reg [4:0] debug_bck_counter
);

reg [4:0] bck_counter = 0;
reg [23:0] left_shift_reg;
reg [23:0] right_shift_reg;
reg lrck_prev = 0;

always @(negedge i_bck) begin
    lrck_prev <= i_lrck;
    debug_bck_counter <= bck_counter;

    if (i_lrck != lrck_prev) begin
        bck_counter <= 0;
        current_channel <= i_lrck;
        o_data_valid <= 1'b0;
    end else begin
        if (bck_counter < 31) begin
            bck_counter <= bck_counter + 1;
        end
    end

    // 数据移位
    if (bck_counter >= 1 && bck_counter <= 24) begin
        if (current_channel == 1'b0) begin
            left_shift_reg <= {left_shift_reg[22:0], i_data};
        end else begin
            right_shift_reg <= {right_shift_reg[22:0], i_data};
        end
    end

    // 产生数据有效信号
    if (bck_counter == 25) begin
        o_data_valid <= 1'b1;
        o_left_data <= left_shift_reg;
        o_right_data <= right_shift_reg;
    end else begin
        o_data_valid <= 1'b0;
    end
end

endmodule

// ==================== I2S发送器 ====================
module parallel_to_i2s (
    input wire i_bck,
    input wire i_lrck,
    input wire [23:0] i_left_data,
    input wire [23:0] i_right_data, 
    output reg o_serial_data
);

reg [4:0] bit_counter = 0;
reg [23:0] shift_reg;
reg lrck_prev = 0;

always @(negedge i_bck) begin
    lrck_prev <= i_lrck;
    
    // 检测LRCK边沿
    if (i_lrck != lrck_prev) begin
        bit_counter <= 5'd0;
        // 根据LRCK选择左右声道数据
        if (i_lrck == 1'b0) begin
            shift_reg <= i_left_data;
        end else begin
            shift_reg <= i_right_data;
        end
    end else begin
        // 串行输出数据
        if (bit_counter < 24) begin
            o_serial_data <= shift_reg[23];
            shift_reg <= {shift_reg[22:0], 1'b0};
        end else begin
            o_serial_data <= 1'b0;
        end
        
        // 位计数器递增
        if (bit_counter < 31) begin
            bit_counter <= bit_counter + 1;
        end
    end
end

endmodule