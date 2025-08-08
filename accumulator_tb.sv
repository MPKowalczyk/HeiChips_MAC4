// Testbench for Accumulator Module
// Tests the accumulation of multiple BIT_WIDTH numbers via 4-bit serial interface

`timescale 1ns / 1ps

module accumulator_tb ();

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
    logic [BIT_WIDTH-1:0] test_numbers[50];
    logic [BIT_WIDTH-1:0] expected_result;
    logic [BIT_WIDTH-1:0] received_result;
    int test_count = 0;
    int pass_count = 0;
    int fail_count = 0;
    int numbers_to_add = 0;
    int current_number_index = 0;

    // State machine states
    typedef enum logic [3:0] {
        IDLE,
        RESET_WAIT,
        WAIT_READY,
        SEND_START,
        SEND_NUMBER_NIBBLES,
        WAIT_COMPLETE,
        CHECK_RESULT,
        NEXT_TEST,
        FINISH
    } tb_state_t;

    // State machine registers
    tb_state_t state, next_state;
    logic [7:0] cycle_counter;
    logic [3:0] nibble_counter;  // Counter for nibbles within a number
    logic [2:0] current_test;    // Current test index
    logic [2:0] output_nibble_counter;  // Counter for received output nibbles

    // Test data for different test cases
    logic [BIT_WIDTH-1:0] test_case_0[3];  // Test 0: Add 3 numbers
    logic [BIT_WIDTH-1:0] test_case_1[2];  // Test 1: Add 2 numbers
    logic [BIT_WIDTH-1:0] test_case_2[4];  // Test 2: Add 4 numbers
    logic [BIT_WIDTH-1:0] test_case_3[1];  // Test 3: Add 1 number (edge case)
    logic [BIT_WIDTH-1:0] test_case_4[5];  // Test 4: Add 5 numbers

    // Expected results for each test case
    logic [BIT_WIDTH-1:0] expected_results[5];

    // Instantiate the DUT (Device Under Test)
    accumulator #(
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
        $dumpfile("accumulator_tb.vcd");
        $dumpvars(0, accumulator_tb);

        // Test Case 0: Add 3 numbers: 10 + 20 + 30 = 60
        test_case_0[0] = 16'd10;
        test_case_0[1] = 16'd20;
        test_case_0[2] = 16'd30;
        expected_results[0] = 16'd60;

        // Test Case 1: Add 2 numbers: 100 + 200 = 300
        test_case_1[0] = 16'd100;
        test_case_1[1] = 16'd200;
        expected_results[1] = 16'd300;

        // Test Case 2: Add 4 numbers: 1 + 2 + 3 + 4 = 10
        test_case_2[0] = 16'd1;
        test_case_2[1] = 16'd2;
        test_case_2[2] = 16'd3;
        test_case_2[3] = 16'd4;
        expected_results[2] = 16'd10;

        // Test Case 3: Add 1 number: 42 = 42 (edge case)
        test_case_3[0] = 16'd42;
        expected_results[3] = 16'd42;

        // Test Case 4: Add 5 numbers: 0x1000 + 0x2000 + 0x3000 + 0x4000 + 0x6000 = 0x10000 (overflow test)
        test_case_4[0] = 16'h1000;
        test_case_4[1] = 16'h2000;
        test_case_4[2] = 16'h3000;
        test_case_4[3] = 16'h4000;
        test_case_4[4] = 16'h6000;
        expected_results[4] = (16'h1000 + 16'h2000 + 16'h3000 + 16'h4000 + 16'h6000) & {BIT_WIDTH{1'b1}};

        $display("Starting Accumulator Testbench");
        $display("BIT_WIDTH = %0d, NIBBLES_PER_INPUT = %0d", BIT_WIDTH, NIBBLES_PER_INPUT);
    end

    // Function to set up test numbers for current test
    function void setup_test_case(int test_idx);
        case (test_idx)
            0: begin
                test_numbers[0] = test_case_0[0];
                test_numbers[1] = test_case_0[1];
                test_numbers[2] = test_case_0[2];
                numbers_to_add = 3;
            end
            1: begin
                test_numbers[0] = test_case_1[0];
                test_numbers[1] = test_case_1[1];
                numbers_to_add = 2;
            end
            2: begin
                test_numbers[0] = test_case_2[0];
                test_numbers[1] = test_case_2[1];
                test_numbers[2] = test_case_2[2];
                test_numbers[3] = test_case_2[3];
                numbers_to_add = 4;
            end
            3: begin
                test_numbers[0] = test_case_3[0];
                numbers_to_add = 1;
            end
            4: begin
                test_numbers[0] = test_case_4[0];
                test_numbers[1] = test_case_4[1];
                test_numbers[2] = test_case_4[2];
                test_numbers[3] = test_case_4[3];
                test_numbers[4] = test_case_4[4];
                numbers_to_add = 5;
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
                data_in <= 4'h0;
                received_result <= '0;
                output_nibble_counter <= 0;
                current_number_index <= 0;
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
                setup_test_case(current_test);
                expected_result <= expected_results[current_test];
                test_count <= test_count + 1;
                current_number_index <= 0;
                
                start <= 1;
                data_in <= test_numbers[0][3:0]; // First nibble of first number
                nibble_counter <= 1; // Next nibble index
                output_nibble_counter <= 0; // Reset output counter
                
                $display("\n=== Test %0d ===", test_count);
                $display("Adding %0d numbers:", numbers_to_add);
                for (int i = 0; i < numbers_to_add; i++) begin
                    $display("  Number %0d: %0d (0x%h)", i, test_numbers[i], test_numbers[i]);
                end
                $display("Expected result: %0d (0x%h)", expected_results[current_test], expected_results[current_test]);
            end
            
            SEND_NUMBER_NIBBLES: begin
                // Determine if we should assert start (for continuing or stopping accumulation)
                if (current_number_index == numbers_to_add - 1 && nibble_counter == 3) begin
                    // Last nibble of last number - assert start to stop accumulation
                    start <= 1;
                end else if (nibble_counter == 3) begin
                    // Last nibble of current number but not last number - deassert start
                    start <= 0;
                end else begin
                    // Middle of a number - keep start deasserted
                    start <= 0;
                end
                
                // Send the appropriate nibble
                case (nibble_counter)
                    1: data_in <= test_numbers[current_number_index][7:4];   // Nibble 1
                    2: data_in <= test_numbers[current_number_index][11:8];  // Nibble 2
                    3: data_in <= test_numbers[current_number_index][15:12]; // Nibble 3
                    default: data_in <= 4'h0;
                endcase
                nibble_counter <= nibble_counter + 1;
                
                // Check if we finished sending current number
                if (nibble_counter == 3) begin
                    nibble_counter <= 0;
                    if (current_number_index < numbers_to_add - 1) begin
                        current_number_index <= current_number_index + 1;
                        // Prepare first nibble of next number for next cycle
                        // (Will be sent in next state cycle)
                    end
                end
                
                // Collect output nibbles
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
                
                // Prepare next number's first nibble when transitioning to next number
                if (nibble_counter == 0 && current_number_index < numbers_to_add) begin
                    data_in <= test_numbers[current_number_index][3:0]; // First nibble of next number
                    nibble_counter <= 1;
                end
            end
            
            WAIT_COMPLETE: begin
                data_in <= 4'h0;
                start <= 0;
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
                current_number_index <= 0;
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
                next_state = SEND_NUMBER_NIBBLES;
            end
            
            SEND_NUMBER_NIBBLES: begin
                // Check if we've sent all numbers and all nibbles
                if (current_number_index >= numbers_to_add - 1 && nibble_counter >= 3) begin
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
