// sv_assert_macros.svh
// Useful macros for basic class-based verification assertions

`ifndef SV_ASSERT_MACROS_SVH
`define SV_ASSERT_MACROS_SVH

`define CHECK_EQ(actual, expected, msg="") \
  if ((actual) !== (expected)) begin \
    $error("ASSERTION FAILED: %s | Actual: %0h, Expected: %0h. %s", `"actual`", actual, expected, msg); \
  end

`define CHECK_NE(actual, unexpected, msg="") \
  if ((actual) === (unexpected)) begin \
    $error("ASSERTION FAILED: %s | Actual: %0h was unexpected. %s", `"actual`", actual, msg); \
  end

`endif // SV_ASSERT_MACROS_SVH
