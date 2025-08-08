// Accumulator Module
// Receives BIT_WIDTH numbers sequentially on a 4-bit input port
// and accumulates them into a running sum

module accumulator #(
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
    localparam int OUTPUT_WIDTH = BIT_WIDTH;       // Result width (input width + some extra bits for overflow)
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
    logic [OUTPUT_WIDTH-1:0] accumulator = 'd0;                       // Accumulator register
    logic [NIBBLE_COUNTER_WIDTH-1:0] nibble_counter = 'd0;            // Counter for 4-bit nibbles (reused for input and output)

    // Reset logic
    always_ff @(posedge clk) begin
        current_state <= next_state;
    end

    // State machine combinational logic
    always_comb begin
        next_state = current_state;
        case (current_state)
            IDLE: begin
                if (start) begin
                    next_state = RECV_DATA;
                end
            end
            
            RECV_DATA: begin
                // Check if we're at the last nibble and start is high (stop accumulation)
                if (nibble_counter == NIBBLES_PER_INPUT - 1) begin
                    if (start) begin
                        next_state = SEND_RESULT;  // Stop accumulation and send result
                    end else begin
                        next_state = RECV_DATA;    // Continue with next number
                    end
                end
            end
            
            SEND_RESULT: begin
                if (nibble_counter == OUTPUT_NIBBLES - 1) begin  // Sent all nibbles
                    next_state = DONE;
                end
            end
            
            DONE: begin
                if (start) begin
                    next_state = RECV_DATA;
                end else begin
                    next_state = IDLE;
                end
            end
        endcase
    end

    // Data reception and accumulation logic
    always_ff @(posedge clk) begin
        case (current_state)
            IDLE: begin
                nibble_counter <= '0;
                // Handle start signal simultaneous with first chunk
                if (start) begin
                    // Clear accumulator and add first nibble directly
                    accumulator <= {{(OUTPUT_WIDTH-4){1'b0}}, data_in};  // First nibble (LSB) 
                    nibble_counter <= 1'b1;  // Start from 1 since we already received first nibble
                end
            end
            
            RECV_DATA: begin
                // Add current nibble directly to accumulator at correct position
                accumulator <= accumulator + ({{(OUTPUT_WIDTH-4){1'b0}}, data_in} << (nibble_counter * 4));
                nibble_counter <= nibble_counter + 1'b1;
                
                if (nibble_counter == NIBBLES_PER_INPUT - 1) begin
                    nibble_counter <= '0;  // Reset for next number or output
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
                if (start) begin
                    // Start new accumulation session - clear and add first nibble
                    accumulator <= {{(OUTPUT_WIDTH-4){1'b0}}, data_in};  // First nibble (LSB)
                    nibble_counter <= 1'b1;
                end else begin
                    // Clear accumulator when going to IDLE
                    accumulator <= '0;
                end
            end
            
            default: begin
                nibble_counter <= '0;
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
