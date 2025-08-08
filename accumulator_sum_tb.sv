// Testbench for Accumulator Sum Module
// Tests the accumulation of pairs of BIT_WIDTH numbers via dual 4-bit serial interface

`timescale 1ns / 1ps

module accumulator_sum_tb ();

    // Parameters
    parameter int BIT_WIDTH = 16;  // Start with smaller width for easier verification
    parameter int NIBBLES_PER_INPUT = BIT_WIDTH / 4;
    parameter int OUTPUT_WIDTH = BIT_WIDTH + $clog2(BIT_WIDTH) + 1;
    parameter int OUTPUT_NIBBLES = OUTPUT_WIDTH / 4;
    
    // Clock period
    parameter real CLK_PERIOD = 100.0; // 100ns = 10MHz
    parameter int TEST_NUMBER = 6; // Number of tests to run

    // Testbench signals
    logic clk;
    logic start;
    logic clear;
    logic [3:0] data_in_a;
    logic [3:0] data_in_b;
    logic [3:0] data_out;
    logic data_out_valid;
    logic result_complete;
    logic ready;
    logic response;

    // Test variables
    logic [BIT_WIDTH-1:0] test_numbers_a[50];
    logic [BIT_WIDTH-1:0] test_numbers_b[50];
    logic [OUTPUT_WIDTH-1:0] expected_result;
    logic [OUTPUT_WIDTH-1:0] received_result;
    int test_count = 0;
    int pass_count = 0;
    int fail_count = 0;
    int pairs_to_add = 0;
    int current_pair_index = 0;

    // State machine states
    typedef enum logic [3:0] {
        IDLE,
        RESET_WAIT,
        WAIT_READY,
        SEND_START,
        SEND_PAIR_NIBBLES,
        CLEAR_TEST,
        WAIT_COMPLETE,
        CHECK_RESULT,
        NEXT_TEST,
        FINISH
    } tb_state_t;

    // State machine registers
    tb_state_t state, next_state;
    logic [7:0] cycle_counter;
    logic [3:0] nibble_counter;  // Counter for nibbles within a pair
    logic [2:0] current_test;    // Current test index
    logic [3:0] output_nibble_counter;  // Counter for received output nibbles

    // Test data for different test cases
    logic [BIT_WIDTH-1:0] test_case_0_a[2];  // Test 0: Add 2 pairs
    logic [BIT_WIDTH-1:0] test_case_0_b[2];
    logic [BIT_WIDTH-1:0] test_case_1_a[3];  // Test 1: Add 3 pairs
    logic [BIT_WIDTH-1:0] test_case_1_b[3];
    logic [BIT_WIDTH-1:0] test_case_2_a[1];  // Test 2: Add 1 pair (edge case)
    logic [BIT_WIDTH-1:0] test_case_2_b[1];
    logic [BIT_WIDTH-1:0] test_case_3_a[4];  // Test 3: Add 4 pairs
    logic [BIT_WIDTH-1:0] test_case_3_b[4];
    logic [BIT_WIDTH-1:0] test_case_4_a[2];  // Test 4: Add 2 pairs, then clear
    logic [BIT_WIDTH-1:0] test_case_4_b[2];
    logic [BIT_WIDTH-1:0] test_case_5_a[3];  // Test 5: Accumulate across multiple sessions
    logic [BIT_WIDTH-1:0] test_case_5_b[3];

    // Expected results for each test case
    logic [OUTPUT_WIDTH-1:0] expected_results[6];
    logic test_uses_clear[6];  // Flag for tests that use clear functionality

    // Instantiate the DUT (Device Under Test)
    accumulator_sum #(
        .BIT_WIDTH(BIT_WIDTH)
    ) dut (
        .clk(clk),
        .start(start),
        .clear(clear),
        .data_in_a(data_in_a),
        .data_in_b(data_in_b),
        .data_out(data_out),
        .data_out_valid(data_out_valid),
        .result_complete(result_complete),
        .ready(ready),
        .response(response)
    );

    // Clock generation
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    // Initialize test data
    initial begin
        $dumpfile("accumulator_sum_tb.vcd");
        $dumpvars(0, accumulator_sum_tb);

        // Test Case 0: Add 2 pairs: (10+20) + (30+40) = 100
        test_case_0_a[0] = 16'd10;  test_case_0_b[0] = 16'd20;
        test_case_0_a[1] = 16'd30;  test_case_0_b[1] = 16'd40;
        expected_results[0] = 32'd100;
        test_uses_clear[0] = 1'b1;

        // Test Case 1: Add 3 pairs: (100+200) + (50+150) + (25+75) = 600
        test_case_1_a[0] = 16'd100; test_case_1_b[0] = 16'd200;
        test_case_1_a[1] = 16'd50;  test_case_1_b[1] = 16'd150;
        test_case_1_a[2] = 16'd25;  test_case_1_b[2] = 16'd75;
        expected_results[1] = 32'd600;
        test_uses_clear[1] = 1'b1;

        // Test Case 2: Add 1 pair: (42+58) = 100 (edge case)
        test_case_2_a[0] = 16'd42;  test_case_2_b[0] = 16'd58;
        expected_results[2] = 32'd100;
        test_uses_clear[2] = 1'b1;

        // Test Case 3: Add 4 pairs: (1+1) + (2+2) + (3+3) + (4+4) = 20
        test_case_3_a[0] = 16'd1;   test_case_3_b[0] = 16'd1;
        test_case_3_a[1] = 16'd2;   test_case_3_b[1] = 16'd2;
        test_case_3_a[2] = 16'd3;   test_case_3_b[2] = 16'd3;
        test_case_3_a[3] = 16'd4;   test_case_3_b[3] = 16'd4;
        expected_results[3] = 32'd20;
        test_uses_clear[3] = 1'b1;

        // Test Case 4: Clear test - add pairs then clear
        test_case_4_a[0] = 16'd100; test_case_4_b[0] = 16'd200;
        test_case_4_a[1] = 16'd300; test_case_4_b[1] = 16'd400;
        expected_results[4] = 32'd1000;  // Should be 0 after clear
        test_uses_clear[4] = 1'b1;

        // Test Case 5: Persistent accumulation - builds on previous results
        test_case_5_a[0] = 16'd10;  test_case_5_b[0] = 16'd10;
        test_case_5_a[1] = 16'd20;  test_case_5_b[1] = 16'd20;
        test_case_5_a[2] = 16'd30;  test_case_5_b[2] = 16'd30;
        expected_results[5] = 32'd120;  // Should accumulate with previous test results
        test_uses_clear[5] = 1'b1;

        $display("Starting Accumulator Sum Testbench");
        $display("BIT_WIDTH = %0d, OUTPUT_WIDTH = %0d, NIBBLES_PER_INPUT = %0d", BIT_WIDTH, OUTPUT_WIDTH, NIBBLES_PER_INPUT);
    end

    // Function to set up test pairs for current test
    function void setup_test_case(int test_idx);
        case (test_idx)
            0: begin
                test_numbers_a[0] = test_case_0_a[0]; test_numbers_b[0] = test_case_0_b[0];
                test_numbers_a[1] = test_case_0_a[1]; test_numbers_b[1] = test_case_0_b[1];
                pairs_to_add = 2;
            end
            1: begin
                test_numbers_a[0] = test_case_1_a[0]; test_numbers_b[0] = test_case_1_b[0];
                test_numbers_a[1] = test_case_1_a[1]; test_numbers_b[1] = test_case_1_b[1];
                test_numbers_a[2] = test_case_1_a[2]; test_numbers_b[2] = test_case_1_b[2];
                pairs_to_add = 3;
            end
            2: begin
                test_numbers_a[0] = test_case_2_a[0]; test_numbers_b[0] = test_case_2_b[0];
                pairs_to_add = 1;
            end
            3: begin
                test_numbers_a[0] = test_case_3_a[0]; test_numbers_b[0] = test_case_3_b[0];
                test_numbers_a[1] = test_case_3_a[1]; test_numbers_b[1] = test_case_3_b[1];
                test_numbers_a[2] = test_case_3_a[2]; test_numbers_b[2] = test_case_3_b[2];
                test_numbers_a[3] = test_case_3_a[3]; test_numbers_b[3] = test_case_3_b[3];
                pairs_to_add = 4;
            end
            4: begin
                test_numbers_a[0] = test_case_4_a[0]; test_numbers_b[0] = test_case_4_b[0];
                test_numbers_a[1] = test_case_4_a[1]; test_numbers_b[1] = test_case_4_b[1];
                pairs_to_add = 2;
            end
            5: begin
                test_numbers_a[0] = test_case_5_a[0]; test_numbers_b[0] = test_case_5_b[0];
                test_numbers_a[1] = test_case_5_a[1]; test_numbers_b[1] = test_case_5_b[1];
                test_numbers_a[2] = test_case_5_a[2]; test_numbers_b[2] = test_case_5_b[2];
                pairs_to_add = 3;
            end
        endcase
    endfunction

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
                clear <= 0;
                data_in_a <= 4'h0;
                data_in_b <= 4'h0;
                received_result <= '0;
                output_nibble_counter <= 0;
                current_pair_index <= 0;
            end
            
            RESET_WAIT: begin
                cycle_counter <= cycle_counter + 1;
                start <= 0;
                clear <= 0;
                data_in_a <= 4'h0;
                data_in_b <= 4'h0;
            end
            
            WAIT_READY: begin
                start <= 0;
                clear <= 0;
                data_in_a <= 4'h0;
                data_in_b <= 4'h0;
            end
            
            SEND_START: begin
                setup_test_case(current_test);
                expected_result <= expected_results[current_test];
                // Only increment test_count when starting the first pair of a new test
                if (current_pair_index == 0) begin
                    test_count <= test_count + 1;
                end
                // Don't reset current_pair_index here - it should continue from where it left off
                
                start <= 1;
                clear <= 0;
                data_in_a <= test_numbers_a[current_pair_index][3:0]; // First nibble of current pair A
                data_in_b <= test_numbers_b[current_pair_index][3:0]; // First nibble of current pair B
                nibble_counter <= 1; // Next nibble index
                output_nibble_counter <= 0; // Reset output counter only for first pair
                
                // Display test info only for the first pair of each test
                if (current_pair_index == 0) begin
                    $display("\n=== Test %0d ===", test_count);
                    if (test_uses_clear[current_test]) begin
                        $display("Testing clear functionality - adding pairs then clearing");
                    end else begin
                        $display("Adding %0d pairs:", pairs_to_add);
                    end
                    for (int i = 0; i < pairs_to_add; i++) begin
                        $display("  Pair %0d: %0d + %0d = %0d (0x%h + 0x%h)", 
                                 i, test_numbers_a[i], test_numbers_b[i], 
                                 test_numbers_a[i] + test_numbers_b[i],
                                 test_numbers_a[i], test_numbers_b[i]);
                    end
                    $display("Expected result: %0d (0x%h)", expected_results[current_test], expected_results[current_test]);
                    $display("  Sending pair %0d: %0d + %0d", 
                             current_pair_index, test_numbers_a[current_pair_index], test_numbers_b[current_pair_index]);
                end else begin
                    $display("  Sending pair %0d: %0d + %0d", 
                             current_pair_index, test_numbers_a[current_pair_index], test_numbers_b[current_pair_index]);
                end
            end
            
            SEND_PAIR_NIBBLES: begin
                start <= 0;
                clear <= 0;
                
                // Send the appropriate nibbles for current pair
                case (nibble_counter)
                    1: begin
                        data_in_a <= test_numbers_a[current_pair_index][7:4];   // Nibble 1 A
                        data_in_b <= test_numbers_b[current_pair_index][7:4];   // Nibble 1 B
                    end
                    2: begin
                        data_in_a <= test_numbers_a[current_pair_index][11:8];  // Nibble 2 A
                        data_in_b <= test_numbers_b[current_pair_index][11:8];  // Nibble 2 B
                    end
                    3: begin
                        data_in_a <= test_numbers_a[current_pair_index][15:12]; // Nibble 3 A
                        data_in_b <= test_numbers_b[current_pair_index][15:12]; // Nibble 3 B
                    end
                    default: begin
                        data_in_a <= 4'h0;
                        data_in_b <= 4'h0;
                    end
                endcase
                
                nibble_counter <= nibble_counter + 1;
                
                // Check if we finished sending current pair (after sending nibble 3)
                if (nibble_counter == 3) begin
                    // Move to next pair for next time
                    current_pair_index <= current_pair_index + 1;
                    nibble_counter <= 0;  // Reset for next pair or state transition
                end
                
                // Monitor response signal
                if (response) begin
                    $display("  Response signal active - processing last nibble of pair %0d", current_pair_index);
                end
            end
            
            CLEAR_TEST: begin
                // Send clear command
                start <= 1;
                clear <= 1;
                data_in_a <= 4'h0;
                data_in_b <= 4'h0;
                $display("  Sending clear command");
            end
            
            WAIT_COMPLETE: begin
                data_in_a <= 4'h0;
                data_in_b <= 4'h0;
                start <= 0;
                clear <= 0;
                
                // Collect output nibbles
                if (data_out_valid) begin
                    if (output_nibble_counter < OUTPUT_NIBBLES) begin
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
                            4: begin
                                received_result[19:16] <= data_out;
                                $display("  Received nibble 4: 0x%h", data_out);
                            end
                            5: begin
                                received_result[23:20] <= data_out;
                                $display("  Received nibble 5: 0x%h", data_out);
                            end
                            default: begin
                                $display("  Received additional nibble %0d: 0x%h", output_nibble_counter, data_out);
                            end
                        endcase
                        output_nibble_counter <= output_nibble_counter + 1;
                    end
                end
                
                // Monitor response signal during output
                if (response) begin
                    $display("  Response signal active - sending last output nibble");
                end
            end
            
            CHECK_RESULT: begin
                if (received_result == expected_result) begin
                    $display("✓ PASS: Received %0d (0x%h), Expected %0d (0x%h)", 
                             received_result, received_result, expected_result, expected_result);
                    pass_count <= pass_count + 1;
                end else begin
                    $display("✗ FAIL: Received %0d (0x%h), Expected %0d (0x%h)", 
                             received_result, received_result, expected_result, expected_result);
                    fail_count <= fail_count + 1;
                end
                current_test <= current_test + 1;
                nibble_counter <= 0;
                received_result <= '0;
                output_nibble_counter <= 0;
                current_pair_index <= 0;  // Reset for next test
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
                next_state = SEND_PAIR_NIBBLES;
            end
            
            SEND_PAIR_NIBBLES: begin
                // Check if we've sent all nibbles of current pair
                if (nibble_counter >= 3) begin
                    if (current_pair_index >= pairs_to_add - 1) begin
                        // This was the last pair, proceed based on test type
                        if (test_uses_clear[current_test]) begin
                            next_state = CLEAR_TEST;
                        end else begin
                            next_state = WAIT_COMPLETE;
                        end
                    end else begin
                        // More pairs to send, go back to RESET_WAIT for next pair
                        next_state = RESET_WAIT;
                    end
                end
            end
            
            CLEAR_TEST: begin
                next_state = WAIT_COMPLETE;
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
    //     $monitor("Time=%0t, State=%s, current_test=%0d, ready=%b, start=%b, clear=%b, data_in_a=0x%h, data_in_b=0x%h, data_out=0x%h, valid=%b, complete=%b, response=%b",
    //              $time, state.name(), current_test, ready, start, clear, data_in_a, data_in_b, data_out, data_out_valid, result_complete, response);
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
