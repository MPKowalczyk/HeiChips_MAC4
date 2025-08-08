// Testbench for Radix-2 Multiplier Module
// Tests the multiplication of two BIT_WIDTH numbers via 4-bit serial interface

`timescale 1ns / 1ps

module mul_radix2_tb ();

    // Parameters
    parameter int BIT_WIDTH = 16;  // Start with smaller width for easier verification
    parameter int NIBBLES_PER_INPUT = BIT_WIDTH / 4;
    parameter int OUTPUT_NIBBLES = BIT_WIDTH / 4;
    
    // Clock period
    parameter real CLK_PERIOD = 100.0; // 100ns = 10MHz
    parameter int TEST_NUMBER = 5; // Number of tests to run

    // Testbench signals
    logic clk;
    logic start;
    logic [3:0] data_in;
    logic [3:0] data_out;
    logic data_out_valid;
    logic result_complete;
    logic ready;

    // Test variables
    logic [BIT_WIDTH-1:0] test_a, test_b;
    logic [BIT_WIDTH-1:0] expected_result;
    logic [BIT_WIDTH-1:0] received_result;
    int test_count = 0;
    int pass_count = 0;
    int fail_count = 0;

    // State machine states
    typedef enum logic [3:0] {
        IDLE,
        RESET_WAIT,
        WAIT_READY,
        SEND_START,
        SEND_A_NIBBLES,
        SEND_B_NIBBLES,
        WAIT_COMPLETE,
        CHECK_RESULT,
        NEXT_TEST,
        FINISH
    } tb_state_t;

    // State machine registers
    tb_state_t state, next_state;
    logic [7:0] cycle_counter;
    logic [3:0] nibble_counter;  // Changed from [2:0] to [3:0] to allow counting to 8
    logic [2:0] current_test;    // Changed from [1:0] to [2:0] to allow counting to 5
    logic [2:0] output_nibble_counter;  // Counter for received output nibbles

    // Test data arrays
    logic [BIT_WIDTH-1:0] test_a_values [0:4];  // Expanded to hold 5 tests (0-4)
    logic [BIT_WIDTH-1:0] test_b_values [0:4];  // Expanded to hold 5 tests (0-4)
    logic [BIT_WIDTH-1:0] expected_values [0:4]; // Expanded to hold 5 tests (0-4)

    // Instantiate the DUT (Device Under Test)
    mul_radix2 #(
        .BIT_WIDTH(BIT_WIDTH)
    ) dut (
        .clk(clk),
        .start(start),
        .data_in(data_in),
        .data_out(data_out),
        .data_out_valid(data_out_valid),
        .result_complete(result_complete),
        .ready(ready)
    );

    // Clock generation
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    // Initialize test data
    initial begin
        $dumpfile("mul_radix2_tb.vcd");
        $dumpvars(0, mul_radix2_tb);

        // Test Case 0: 0 × 0 = 0
        test_a_values[0] = 16'h0000;
        test_b_values[0] = 16'h0000;
        expected_values[0] = 16'h0000;

        // Test Case 1: 0x4321 × 0x8765
        test_a_values[1] = 16'h0001;
        test_b_values[1] = 16'h0001;
        expected_values[1] = (test_a_values[1] * test_b_values[1]) & {BIT_WIDTH{1'b1}};

        // Test Case 2: 2 × 3 = 6
        test_a_values[2] = 16'h0002;
        test_b_values[2] = 16'h0003;
        expected_values[2] = (test_a_values[2] * test_b_values[2]) & {BIT_WIDTH{1'b1}};

        // Test Case 3: 34 * 26 = 884
        test_a_values[3] = 16'd34;
        test_b_values[3] = 16'd26;
        expected_values[3] = (test_a_values[3] * test_b_values[3]) & {BIT_WIDTH{1'b1}};

        // Test Case 4: 0x1234 × 0x5678
        test_a_values[4] = 16'h1234;
        test_b_values[4] = 16'h5678;
        expected_values[4] = (test_a_values[4] * test_b_values[4]) & {BIT_WIDTH{1'b1}};

        $display("Starting Radix-2 Multiplier Testbench");
        $display("BIT_WIDTH = %0d, NIBBLES_PER_INPUT = %0d", BIT_WIDTH, NIBBLES_PER_INPUT);
    end

    // State machine sequential logic
    always_ff @(posedge clk) begin
        state <= next_state;
        
        case (state)
            IDLE: begin
                cycle_counter <= 0;
                nibble_counter <= 0;
                current_test <= 0;
                test_count <= 0;
                pass_count <= 0;
                fail_count <= 0;
                start <= 0;
                data_in <= 4'h0;
                received_result <= '0;
                output_nibble_counter <= 0;
            end
            
            RESET_WAIT: begin
                cycle_counter <= cycle_counter + 1;
                start <= 0;
                data_in <= 4'h0;
            end
            
            WAIT_READY: begin
                start <= 0;
                data_in <= 4'h0;
            end
            
            SEND_START: begin
                test_a <= test_a_values[current_test];
                test_b <= test_b_values[current_test];
                expected_result <= expected_values[current_test];
                test_count <= test_count + 1;
                
                start <= 1;
                data_in <= test_a_values[current_test][3:0]; // First nibble of A
                nibble_counter <= 1; // Next nibble index
                output_nibble_counter <= 0; // Reset output counter
                
                $display("\n=== Test %0d ===", test_count + 1);
                $display("Testing: %0d × %0d = %0d (0x%h × 0x%h = 0x%h)", 
                         test_a_values[current_test], test_b_values[current_test], expected_values[current_test],
                         test_a_values[current_test], test_b_values[current_test], expected_values[current_test]);
            end
            
            SEND_A_NIBBLES: begin
                start <= 0;
                case (nibble_counter)
                    1: data_in <= test_a[7:4];   // Nibble 1
                    2: data_in <= test_a[11:8];  // Nibble 2
                    3: data_in <= test_a[15:12]; // Nibble 3
                    default: data_in <= 4'h0;
                endcase
                nibble_counter <= nibble_counter + 1;
            end
            
            SEND_B_NIBBLES: begin
                case (nibble_counter - 4)
                    0: data_in <= test_b[3:0];   // Nibble 0 of B
                    1: data_in <= test_b[7:4];   // Nibble 1 of B
                    2: data_in <= test_b[11:8];  // Nibble 2 of B
                    3: data_in <= test_b[15:12]; // Nibble 3 of B
                    default: data_in <= 4'h0;
                endcase
                nibble_counter <= nibble_counter + 1;
                
                // Collect output nibbles based on output_nibble_counter
                if (data_out_valid) begin
                    case (output_nibble_counter)
                        0: begin
                            received_result[3:0] <= data_out;
                            $display("  Received nibble 0: 0x%h", data_out);
                        end
                        1: begin
                            received_result[7:4] <= data_out;
                            $display("  Received nibble 1: 0x%h", data_out);
                        end
                        2: begin
                            received_result[11:8] <= data_out;
                            $display("  Received nibble 2: 0x%h", data_out);
                        end
                        3: begin
                            received_result[15:12] <= data_out;
                            $display("  Received nibble 3: 0x%h", data_out);
                        end
                    endcase
                    output_nibble_counter <= output_nibble_counter + 1;
                end
            end
            
            WAIT_COMPLETE: begin
                data_in <= 4'h0;
                // Collect any remaining output nibbles
                if (data_out_valid) begin
                    case (output_nibble_counter)
                        0: begin
                            received_result[3:0] <= data_out;
                            $display("  Received nibble 0: 0x%h", data_out);
                        end
                        1: begin
                            received_result[7:4] <= data_out;
                            $display("  Received nibble 1: 0x%h", data_out);
                        end
                        2: begin
                            received_result[11:8] <= data_out;
                            $display("  Received nibble 2: 0x%h", data_out);
                        end
                        3: begin
                            received_result[15:12] <= data_out;
                            $display("  Received nibble 3: 0x%h", data_out);
                        end
                    endcase
                    output_nibble_counter <= output_nibble_counter + 1;
                end
            end
            
            CHECK_RESULT: begin
                if (received_result == expected_result) begin
                    $display("✓ PASS: Received 0x%h, Expected 0x%h", received_result, expected_result);
                    pass_count <= pass_count + 1;
                end else begin
                    $display("✗ FAIL: Received 0x%h, Expected 0x%h", received_result, expected_result);
                    fail_count <= fail_count + 1;
                end
                current_test <= current_test + 1;
                nibble_counter <= 0;
                received_result <= '0;
                output_nibble_counter <= 0;
            end
            
            NEXT_TEST: begin
                $display("DEBUG: current_test=%0d, TEST_NUMBER=%0d", current_test, TEST_NUMBER);
                // Just transition state
            end
            
            FINISH: begin
                $display("\n=== Test Summary ===");
                $display("Total Tests: %0d", test_count);
                $display("Passed: %0d", pass_count);
                $display("Failed: %0d", fail_count);
                
                if (fail_count == 0) begin
                    $display("🎉 ALL TESTS PASSED!");
                end else begin
                    $display("❌ SOME TESTS FAILED!");
                end
                
                cycle_counter <= cycle_counter + 1;
                if (cycle_counter >= 10) begin
                    $finish;
                end
            end
        endcase
    end

    // State machine combinational logic
    always_comb begin
        next_state = state;
        
        case (state)
            IDLE: begin
                next_state = RESET_WAIT;
            end
            
            RESET_WAIT: begin
                if (cycle_counter >= 5) begin
                    next_state = WAIT_READY;
                end
            end
            
            WAIT_READY: begin
                if (ready) begin
                    next_state = SEND_START;
                end
            end
            
            SEND_START: begin
                next_state = SEND_A_NIBBLES;
            end
            
            SEND_A_NIBBLES: begin
                if (nibble_counter >= 3) begin
                    next_state = SEND_B_NIBBLES;
                end
            end
            
            SEND_B_NIBBLES: begin
                if (nibble_counter >= 7) begin
                    next_state = WAIT_COMPLETE;
                end
            end
            
            WAIT_COMPLETE: begin
                if (result_complete) begin
                    next_state = CHECK_RESULT;
                end
            end
            
            CHECK_RESULT: begin
                next_state = NEXT_TEST;
            end
            
            NEXT_TEST: begin
                if (current_test >= TEST_NUMBER) begin
                    next_state = FINISH;
                end else begin
                    next_state = WAIT_READY;
                end
            end
            
            FINISH: begin
                // Stay in finish state
            end
            
            default: begin
                next_state = IDLE;
            end
        endcase
    end

    // Monitor for debugging
    // initial begin
    //     $monitor("Time=%0t, State=%s, current_test=%0d, test_count=%0d, ready=%b, start=%b, data_in=0x%h, data_out=0x%h, valid=%b, complete=%b",
    //              $time, state.name(), current_test, test_count, ready, start, data_in, data_out, data_out_valid, result_complete);
    // end

    // Timeout watchdog
    logic [15:0] timeout_counter;
    always_ff @(posedge clk) begin
        if (state == IDLE) begin
            timeout_counter <= 0;
        end else begin
            timeout_counter <= timeout_counter + 1;
            if (timeout_counter >= 10000) begin
                $display("ERROR: Testbench timeout!");
                $finish;
            end
        end
    end

endmodule
