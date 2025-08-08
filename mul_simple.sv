// Simple 4-bit multiplier module
// Multiplies two 4-bit unsigned numbers to produce an 8-bit result

module mul_simple (
    input  logic       clk,     // Clock signal
    input  logic       enable,  // Enable signal
    input  logic [3:0] a,       // First 4-bit input
    input  logic [3:0] b,       // Second 4-bit input
    output logic [7:0] product  // 8-bit product output
);

    // Clocked multiplication process
    always_ff @(posedge clk) begin
        if (enable) begin
            product <= a * b;
        end
    end

endmodule