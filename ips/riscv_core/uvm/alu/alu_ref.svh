function automatic void alu_ref(input bit [31:0] a, input bit [31:0] b, input bit [3:0] ctl,
                                output bit [31:0] res, output bit zero, output bit [2:0] flags);
  bit [4:0] sh = b[4:0];
  case (ctl)
    4'b0000: res = a + b;
    4'b0001: res = a - b;
    4'b0100: res = a & b;
    4'b0101: res = a | b;
    4'b0110: res = (a + b) & 32'hFFFF_FFFE;
    4'b0111: res = a ^ b;
    4'b1000: res = a << sh;
    4'b1001: res = a >> sh;
    4'b1010: res = $unsigned($signed(a) >>> sh);
    4'b1100: res = {31'd0, a < b};
    4'b1111: res = {31'd0, $signed(a) < $signed(b)};
    default: res = 32'd0;
  endcase
  zero  = (res == 32'd0);
  flags = {a == b, $signed(a) < $signed(b), a < b};
endfunction
