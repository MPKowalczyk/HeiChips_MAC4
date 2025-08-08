// Radix-2 Multiplier Module
// Receives two BIT_WIDTH numbers sequentially on a 4-bit input port
// and multiplies them using radix-2 (shift-and-add) algorithm

module mul_radix2 #(
    parameter int BIT_WIDTH = 32  // Width of each input operand
) (
    input  logic        clk,
    input  logic        start,          // Start signal to begin data reception
    input  logic [3:0]  data_in,        // 4-bit input data port
    output logic [3:0]  data_out,       // 4-bit output data port
    output logic        data_out_valid,  // Output data valid signal
    output logic        result_complete, // Complete result transmission finished
    output logic        ready           // Ready for new operation
);

    // Derived parameters
    localparam int NIBBLES_PER_INPUT = BIT_WIDTH / 4;  // Number of 4-bit nibbles per input
    localparam int OUTPUT_WIDTH = BIT_WIDTH;       // Result width (2x input width)
    localparam int OUTPUT_NIBBLES = OUTPUT_WIDTH / 4;  // Number of output nibbles
    localparam int NIBBLE_COUNTER_WIDTH = $clog2(NIBBLES_PER_INPUT); // Width for nibble counter
    localparam int BIT_COUNTER_WIDTH = $clog2(BIT_WIDTH);       // Width for bit counter

    // State machine states
    typedef enum logic [1:0] {
        IDLE         = 2'b00,
        RECV_A       = 2'b01,
        RECV_B_MUL   = 2'b10,  // Receive B, multiply, and send first part of result
        DONE         = 2'b11   // Send last nibble and complete
    } state_t;

    state_t current_state = IDLE;
    state_t next_state = IDLE;

    // Internal registers
    logic [OUTPUT_WIDTH-1:0] product;                           // Accumulator for multiplication
    logic [BIT_COUNTER_WIDTH-1:0] bit_counter;                  // Counter for multiplication bits
    logic [NIBBLE_COUNTER_WIDTH-1:0] nibble_counter = '0;            // Counter for 4-bit nibbles

    // Data reception shift register (also serves as multiplicand)
    logic [BIT_WIDTH-1:0] recv_shift_reg = '0;  // Shift register for receiving A and B

    // State machine sequential logic
    always_ff @(posedge clk) begin
        current_state <= next_state;
    end

    // State machine combinational logic
    always_comb begin
        next_state = current_state;
        case (current_state)
            IDLE: begin
                if (start) begin
                    next_state = RECV_A;
                end
            end
            
            RECV_A: begin
                if (nibble_counter == NIBBLES_PER_INPUT - 1) begin  // Received all nibbles
                    next_state = RECV_B_MUL;
                end
            end
            
            RECV_B_MUL: begin
                if (nibble_counter == NIBBLES_PER_INPUT - 1) begin  // Received all of B and processed all multiplications
                    next_state = DONE;
                end
            end
            
            DONE: begin
                next_state = IDLE;
            end
        endcase
    end

    // Data reception logic
    always_ff @(posedge clk) begin
        case (current_state)
            IDLE: begin
                if (start) begin
                    // Receive first nibble simultaneously with start signal
                    recv_shift_reg <= {data_in, recv_shift_reg[BIT_WIDTH-1:4]};
                    nibble_counter <= 1'b1; // Start from 1 since we already received first nibble
                end
                else begin
                    nibble_counter <= '0;
                    recv_shift_reg <= '0;
                end
            end
            
            RECV_A: begin
                // LSB-first reception: build the number from LSB to MSB
                recv_shift_reg <= {data_in, recv_shift_reg[BIT_WIDTH-1:4]};
                nibble_counter <= nibble_counter + 1'b1;
                if (nibble_counter == NIBBLES_PER_INPUT - 1) begin
                    // recv_shift_reg now contains the complete A number (multiplicand)
                    nibble_counter <= '0;
                end
            end
            
            RECV_B_MUL: begin
                // No longer need to shift recv_shift_reg since it contains multiplicand
                nibble_counter <= nibble_counter + 1'b1;
                if (nibble_counter == NIBBLES_PER_INPUT - 1) begin
                    nibble_counter <= '0;
                end
            end
            
            default: begin
                nibble_counter <= '0;
            end
        endcase
    end

    // Radix-2 multiplication logic (shift-and-add algorithm)
    // Performs multiplication while receiving B number
    always_ff @(posedge clk) begin
        case (current_state)
            
            RECV_B_MUL: begin
                // Process all 4 bits of B nibble in parallel
                // Data comes LSB first: data_in[0] is bit 0, data_in[3] is bit 3 of current nibble
                product <= product + 
                            (data_in[0] ? ({{(OUTPUT_WIDTH-BIT_WIDTH){1'b0}}, recv_shift_reg} << (bit_counter + 0)) : '0) +
                            (data_in[1] ? ({{(OUTPUT_WIDTH-BIT_WIDTH){1'b0}}, recv_shift_reg} << (bit_counter + 1)) : '0) +
                            (data_in[2] ? ({{(OUTPUT_WIDTH-BIT_WIDTH){1'b0}}, recv_shift_reg} << (bit_counter + 2)) : '0) +
                            (data_in[3] ? ({{(OUTPUT_WIDTH-BIT_WIDTH){1'b0}}, recv_shift_reg} << (bit_counter + 3)) : '0);
                
                bit_counter <= bit_counter + 4; // Advance by 4 bits since we processed 4 bits
            end
            
            default: begin
                product <= '0;
                bit_counter <= '0;
            end
        endcase
    end

    // Output logic
    always_ff @(posedge clk) begin
        case (current_state)
            IDLE: begin
                ready <= 1'b1;
                data_out_valid <= 1'b0;
                result_complete <= 1'b0;
                data_out <= 4'h0;
            end
            
            RECV_A: begin
                ready <= 1'b0;
                data_out_valid <= 1'b0;
                result_complete <= 1'b0;
            end
            
            RECV_B_MUL: begin
                ready <= 1'b0;
                result_complete <= 1'b0;
                
                // Start outputting results after first nibble of B is processed
                if (nibble_counter > 0) begin
                    data_out_valid <= 1'b1;
                    // Output the finalized nibbles with 1-cycle delay
                    // Extract the appropriate 4-bit nibble from product
                    data_out <= product[(nibble_counter - 1) * 4 +: 4];
                end else begin
                    data_out_valid <= 1'b0;
                    data_out <= 4'h0;
                end
            end
            
            DONE: begin
                ready <= 1'b0;
                result_complete <= 1'b1;
                data_out_valid <= 1'b1;  // Send the last nibble
                
                // Send the final nibble (last nibble of the result)
                data_out <= product[(OUTPUT_NIBBLES - 1) * 4 +: 4];
            end
        endcase
    end

endmodule
