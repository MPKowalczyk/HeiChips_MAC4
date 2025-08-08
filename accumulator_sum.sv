// Modified Accumulator Module
// Receives two BIT_WIDTH numbers simultaneously on 4-bit input ports
// and accumulates them: accumulator = accumulator + a + b
// Does not auto-clear accumulator - requires explicit clear signal

module accumulator_sum #(
    parameter int BIT_WIDTH = 32  // Width of each input operand
) (
    input  logic        clk,
    input  logic        start,          // Start signal to begin data reception
    input  logic        clear,          // Clear signal to reset accumulator
    input  logic [3:0]  data_in_a,      // 4-bit input data port A
    input  logic [3:0]  data_in_b,      // 4-bit input data port B
    output logic [3:0]  data_out,       // 4-bit output data port
    output logic        data_out_valid,  // Output data valid signal
    output logic        result_complete, // Complete result transmission finished
    output logic        ready,          // Ready for new operation
    output logic        response        // High when receiving last chunk or sending last output chunk
);

    // Derived parameters
    localparam int NIBBLES_PER_INPUT = BIT_WIDTH / 4;  // Number of 4-bit nibbles per input
    localparam int OUTPUT_WIDTH = BIT_WIDTH + $clog2(BIT_WIDTH) + 1;  // Result width with extra bits for accumulation
    localparam int OUTPUT_NIBBLES = OUTPUT_WIDTH / 4;  // Number of output nibbles
    localparam int MAX_NIBBLES = (NIBBLES_PER_INPUT > OUTPUT_NIBBLES) ? NIBBLES_PER_INPUT : OUTPUT_NIBBLES;
    localparam int NIBBLE_COUNTER_WIDTH = $clog2(MAX_NIBBLES); // Width for nibble counter

    // State machine states
    typedef enum logic [2:0] {
        IDLE         = 3'b000,
        RECV_DATA    = 3'b001,
        SEND_RESULT  = 3'b010,
        DONE         = 3'b011
    } state_t;

    state_t current_state = IDLE;
    state_t next_state = IDLE;

    // Internal registers
    logic [OUTPUT_WIDTH-1:0] accumulator = 'd0;                       // Accumulator register (not auto-cleared)
    logic [NIBBLE_COUNTER_WIDTH-1:0] nibble_counter = 'd0;            // Counter for 4-bit nibbles (reused for input and output)

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
                    if (clear) begin
                        next_state = SEND_RESULT;  // Clear and send result immediately
                    end else begin
                        next_state = RECV_DATA;    // Start receiving new data
                    end
                end
            end
            
            RECV_DATA: begin
                // Check if we're at the last nibble (stop receiving)
                if (nibble_counter == NIBBLES_PER_INPUT - 1) begin
                    next_state = IDLE;  // Go back to IDLE after receiving complete numbers
                end
            end
            
            SEND_RESULT: begin
                if (nibble_counter == OUTPUT_NIBBLES - 1) begin  // Sent all nibbles
                    next_state = DONE;
                end
            end
            
            DONE: begin
                next_state = IDLE;  // Always go back to IDLE
            end
        endcase
    end

    // Data reception and accumulation logic
    always_ff @(posedge clk) begin
        case (current_state)
            IDLE: begin
                nibble_counter <= '0;
                
                if (start) begin
                    if (clear) begin
                        // Clear accumulator and go to send result
                        nibble_counter <= '0;
                    end else begin
                        // Start receiving first nibbles of both numbers - add directly to accumulator
                        accumulator <= accumulator + 
                                     {{(OUTPUT_WIDTH-4){1'b0}}, data_in_a} + 
                                     {{(OUTPUT_WIDTH-4){1'b0}}, data_in_b};
                        nibble_counter <= 1'b1;  // Start from 1 since we already processed first nibbles
                    end
                end
            end
            
            RECV_DATA: begin
                // Add current nibbles directly to accumulator at correct position
                accumulator <= accumulator + 
                              ({{(OUTPUT_WIDTH-4){1'b0}}, data_in_a} << (nibble_counter * 4)) +
                              ({{(OUTPUT_WIDTH-4){1'b0}}, data_in_b} << (nibble_counter * 4));
                nibble_counter <= nibble_counter + 1'b1;
                
                if (nibble_counter == NIBBLES_PER_INPUT - 1) begin
                    nibble_counter <= '0;  // Reset for potential output
                end
            end
            
            SEND_RESULT: begin
                // Increment counter to send result nibbles
                nibble_counter <= nibble_counter + 1'b1;
                
                if (nibble_counter == OUTPUT_NIBBLES - 1) begin
                    nibble_counter <= '0;
                end
            end
            
            DONE: begin
                nibble_counter <= '0;
                accumulator <= '0;
            end
            
            default: begin
                nibble_counter <= '0;
            end
        endcase
    end

    // Combinational response logic - active during the current processing of last chunks
    always_comb begin
        response = 1'b0;  // Default value
        
        case (current_state)
            RECV_DATA: begin
                // High when currently processing the last input nibble
                if (nibble_counter == NIBBLES_PER_INPUT - 1) begin
                    response = 1'b1;
                end
            end
            
            SEND_RESULT: begin
                // High when currently sending the last output nibble
                if (nibble_counter == OUTPUT_NIBBLES - 1) begin
                    response = 1'b1;
                end
            end
            
            default: begin
                response = 1'b0;
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
            
            RECV_DATA: begin
                ready <= 1'b0;
                data_out_valid <= 1'b0;
                result_complete <= 1'b0;
                data_out <= 4'h0;
            end
            
            SEND_RESULT: begin
                ready <= 1'b0;
                result_complete <= 1'b0;
                data_out_valid <= 1'b1;
                
                // Extract the appropriate 4-bit nibble from accumulator (LSB first)
                data_out <= accumulator[nibble_counter * 4 +: 4];
            end
            
            DONE: begin
                ready <= 1'b1;
                result_complete <= 1'b1;
                data_out_valid <= 1'b0;
                data_out <= 4'h0;
            end
        endcase
    end

endmodule
