// Compact on-chip trace records for cl_cva6_trackers.
// Instruction rows follow the CVA6 commit/scoreboard view (trans_id, not ROB).
// Cache rows are DRAM-side AXI traffic from the write-through L1 (miss/refill
// and stores), split by AXI ID: 0 = I-cache, 1 = D-cache (wt_cache_subsystem).
// Event rows are a separate always-on FIFO: traps, pipeline flushes, mispredicts.

package cva6_trace_pkg;

  localparam int unsigned INSTR_DEPTH = 1024;
  localparam int unsigned CACHE_DEPTH = 1024;
  localparam int unsigned EVENT_DEPTH = 256;
  localparam int unsigned L1_DEPTH = 2048;
  localparam int unsigned INSTR_WORDS = 16;
  localparam int unsigned CACHE_WORDS = 8;
  localparam int unsigned EVENT_WORDS = 16;
  localparam int unsigned L1_WORDS = 4;

  localparam int unsigned KIND_AR  = 0;
  localparam int unsigned KIND_R   = 1;
  localparam int unsigned KIND_AW  = 2;
  localparam int unsigned KIND_W   = 3;
  localparam int unsigned KIND_B   = 4;
  localparam int unsigned KIND_LSU = 5;
  localparam int unsigned KIND_L1I_MISS = 6;
  localparam int unsigned KIND_L1D_MISS = 7;

  localparam int unsigned EVT_TRAP = 0;
  localparam int unsigned EVT_FLUSH = 1;
  localparam int unsigned EVT_MISP = 2;
  localparam int unsigned EVT_ICMISS = 3;
  localparam int unsigned EVT_DCMISS = 4;

  typedef logic [INSTR_WORDS*64-1:0] instr_rec_t;
  typedef logic [CACHE_WORDS*64-1:0] cache_rec_t;
  typedef logic [EVENT_WORDS*64-1:0] event_rec_t;
  typedef logic [L1_WORDS*64-1:0] l1_rec_t;

endpackage
