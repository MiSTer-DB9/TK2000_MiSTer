//
// TK2000 resets and disk interface enable. Shared by TK2000.sv and the sim
// (verilator/sim.v).
//
// Cold reset (power on, board reset, OSD Apply and reset, ROM load): por_reset
// is held ~0.3 s; while it is held the RAM write port clears $3F4 (the caller
// does that), so the ROM sees a broken power-up byte and does a cold start:
// it checks $C100 for the disk interface and boots the drive if it is there,
// else it starts BASIC.
//
// Warm reset (F2 = the TK2000 RESET keys, OSD Warm reset): only the CPU and
// peripherals are reset, RAM is kept. With the power-up byte intact
// ($3F4 = $3F3 ^ $A5) the ROM jumps through $3F2 to BASIC without looking at
// the disk interface - the way out of an empty drive, or out of a program,
// exactly like Ctrl-Reset on an Apple II. Held while F2 is held, at least
// ~2 ms.
//
// Disk interface (OSD Machine > Disk interface, latched at cold reset):
//   Auto - the $C100 ROM is there only if D1 holds a disk at the cold reset,
//          so a tape-only setup starts in BASIC. Inserting a disk in D1 while
//          the interface is out reboots (cold) into it.
//   On   - always there (real machine with the interface fitted: an empty
//          drive spins until a disk is inserted or F2 is pressed).
//   Off  - never there.
//
module reset_ctrl
(
	input             clk,          // clk_sys (14.318 MHz)
	input             cold_req,     // level: hold in cold reset
	input             warm_req,     // pulse: OSD Warm reset
	input      [10:0] ps2_key,
	input       [1:0] disk_mode,    // 0 Auto, 1 On, 2 Off (raw OSD bits)
	input             d1_mounted,   // D1 holds an image (level)
	input             d1_insert,    // D1 image mounted (pulse, non-empty)
	input             d1_motor,     // drive 1 running

	output reg        por_reset = 1'b1,  // cold: clear $3F4, latch settings
	output reg        reset = 1'b1,      // CPU and peripherals
	output reg        disk_en = 1'b0,    // $C100 disk interface ROM present
	output            warm_active,
	output            empty_spin    // interface on, D1 empty, motor on > ~1 s
);

localparam [1:0] M_AUTO = 2'd0, M_ON = 2'd1;

// F2 (make code 06, not extended), level while held
reg f2_held = 1'b0, old_strobe = 1'b0;
always @(posedge clk) begin
	old_strobe <= ps2_key[10];
	if (ps2_key[10] != old_strobe && !ps2_key[8] && ps2_key[7:0] == 8'h06)
		f2_held <= ps2_key[9];
end

reg  [14:0] warm_cnt = 15'd0;
reg         old_f2 = 1'b0;
assign warm_active = f2_held || warm_cnt != 15'd0;

// Auto: insert into an empty interface -> cold reboot
reg  [1:0] mode = M_AUTO;
reg        old_insert = 1'b0;
reg        auto_boot = 1'b0;

reg [22:0] por_cnt = 23'd0;
always @(posedge clk) begin
	old_f2 <= f2_held;
	old_insert <= d1_insert;
	auto_boot <= 1'b0;
	if (d1_insert && !old_insert && !por_reset && mode == M_AUTO && !disk_en)
		auto_boot <= 1'b1;

	if ((f2_held && !old_f2) || warm_req) warm_cnt <= 15'h7FFF;
	else if (warm_cnt != 15'd0) warm_cnt <= warm_cnt - 15'd1;

	if (cold_req || auto_boot) begin
		por_reset <= 1'b1;
		por_cnt <= 23'd0;
	end else if (por_reset) begin
		if (por_cnt[22]) por_reset <= 1'b0;
		por_cnt <= por_cnt + 23'd1;
	end

	if (por_reset) begin
		mode <= disk_mode;
		disk_en <= disk_mode == M_ON || (disk_mode == M_AUTO && d1_mounted);
	end

	reset <= por_reset | cold_req | warm_active;
end

// The ROM is waiting on an empty drive (for the "PRESS F2 FOR BASIC" hint)
reg [23:0] spin_cnt = 24'd0;
always @(posedge clk)
	if (reset || !disk_en || d1_mounted || !d1_motor) spin_cnt <= 24'd0;
	else if (!spin_cnt[23]) spin_cnt <= spin_cnt + 24'd1;
assign empty_spin = spin_cnt[23];

endmodule
