module tb;
  import config_pkg::*;
  import dv_pkg::*;
  ;
  alu_runner runner ();

  task automatic test_echo(input string message);
    logic [7:0] data[];
    logic [7:0] received[256];
    logic [15:0] packet_len;
    logic [7:0] header[4];
    int msg_len;

    // Convert string to byte array
    msg_len = message.len();
    data = new[msg_len];
    foreach (message[i]) begin
      data[i] = message[i];
    end

    packet_len = 16'd4 + 16'(msg_len);

    $display("Message: %s", message);

    // Set up header
    header[0] = OPCODE_ECHO;
    header[1] = 8'h00;
    header[2] = packet_len[7:0];
    header[3] = packet_len[15:8];

    // Send header bytes
    foreach (header[i]) begin
      runner.send(header[i]);
      // $display("Sent header: %h", header[i]);
    end

    // For data section, send one byte and receive it back immediately
    for (int i = 0; i < msg_len; i++) begin
      runner.send(data[i]);
      // $display("Sent data: %h", data[i]);
      runner.receive(received[i]);
      // $display("Received: %h", received[i]);

      if (received[i] !== data[i]) begin
        $display("FAIL - Mismatch at position %0d: expected %h, got %h", i, data[i], received[i]);
        return;
      end
    end
    $display("PASS");
  endtask

  task automatic send_packet(input logic [7:0] opcode, input logic [15:0] len,
                             input logic [7:0] data[]);
    logic [7:0] header[4];
    header[0] = opcode;
    header[1] = 8'h00;
    header[2] = len[7:0];
    header[3] = len[15:8];

    // Send header
    foreach (header[i]) begin
      runner.send(header[i]);
      // $display("Sent: %h", header[i]);
    end

    // Send data
    foreach (data[i]) begin
      runner.send(data[i]);
      // $display("Sent: %h", data[i]);
    end
  endtask

  task automatic receive_result(output logic [31:0] result);
    logic [7:0] bytes[4];
    foreach (bytes[i]) begin
      runner.receive(bytes[i]);
      // $display("Received byte: %h", bytes[i]);
    end
    result = {bytes[3], bytes[2], bytes[1], bytes[0]};
  endtask

  task automatic test_math(input logic [7:0] opcode, input logic [31:0] operands[],
                           input int num_operands, input logic [31:0] expected);
    logic [7:0] data[];
    logic [31:0] result;
    logic [15:0] packet_len;

    // Convert 32-bit operands to byte array
    data = new[num_operands * 4];
    for (int i = 0; i < num_operands; i++) begin
      data[i*4+3] = operands[i][31:24];
      data[i*4+2] = operands[i][23:16];
      data[i*4+1] = operands[i][15:8];
      data[i*4+0] = operands[i][7:0];
    end

    packet_len = 16'd4 + 16'(data.size());

    $display("Operands: ");
    for (int i = 0; i < num_operands; i++)
      $display("[%0d] = %0d (0x%0h)", i, $signed(operands[i]), operands[i]);
    $display("Expected: %0d (0x%0h)", $signed(expected), expected);

    send_packet(opcode, packet_len, data);
    receive_result(result);

    $display("Received: %0d (0x%0h)", $signed(result), result);

    if (result !== expected) begin
      $display("FAIL");
    end else begin
      $display("PASS");
    end
  endtask

  task automatic random_echo(input int num_tests);
    string chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
    string message;
    int length;

    for (int test = 0; test < num_tests; test++) begin
      length  = $urandom_range(1, 100);  // Random message length between 1-100
      message = "";
      for (int i = 0; i < length; i++) begin
        message = {message, string'(chars[$urandom_range(0, chars.len()-1)])};
      end
      test_echo(message);
    end
  endtask

  task automatic random_math(input logic [7:0] opcode, input int num_tests);
    logic [31:0] operands[];
    logic [31:0] expected;
    int num_operands;

    for (int test = 0; test < num_tests; test++) begin
      // only 2 operands for division
      num_operands = (opcode == OPCODE_DIV) ? 2 : $urandom_range(2, 100);
      operands = new[num_operands];

      // Generate random operands
      foreach (operands[i]) begin
        operands[i] = $urandom();
      end

      // Calculate expected result
      case (opcode)
        OPCODE_ADD: begin
          expected = 0;
          foreach (operands[i]) expected += operands[i];
        end
        OPCODE_MUL: begin
          expected = 1;
          foreach (operands[i]) expected = $signed(expected) * $signed(operands[i]);
        end
        OPCODE_DIV: begin
          if (operands[1] == 0) operands[1] = 1;  // Avoid divide by zero
          // Use $signed for proper signed division
          expected = $signed(operands[0]) / $signed(operands[1]);
        end
        default: begin
          $display("Unknown opcode: %0h", opcode);
          return;
        end
      endcase

      test_math(opcode, operands, num_operands, expected);
    end
  endtask

  initial begin
    $dumpfile("dump.fst");
    $dumpvars;

    runner.reset();

    // test_echo("Hello, World!");
    // test_math(OPCODE_ADD, '{32'h1, 32'h2}, 2, 32'h3);
    // test_math(OPCODE_MUL, '{32'h2, 32'h3}, 2, 32'h6);
    // test_math(OPCODE_DIV, '{32'h6, 32'h2}, 2, 32'h3);

    // $display("Test ECHO with 1 random strings...");
    // random_echo(1);

    $display("\nTest ADD with random inputs...");
    random_math(OPCODE_ADD, 5);

    $display("\nTest MUL with random inputs...");
    random_math(OPCODE_MUL, 5);

    $display("\nTest DIV with random inputs...");
    random_math(OPCODE_DIV, 5);


    $finish;
  end
endmodule
