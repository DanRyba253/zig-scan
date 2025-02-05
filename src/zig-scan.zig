//! Provides functions for formatted input parsing
//! For more info: https://github.com/DanRyba253/zig-scan

const std = @import("std");
const fmt_info = @import("fmt_info.zig");
const peek = @import("peek.zig");
const interface = @import("interface.zig");

fn eqlHandleEscapes(str: []const u8, lit: []const u8) bool {
    var j: usize = 0;
    for (str) |a| {
        if (j >= lit.len) return false;
        const b = lit[j];
        if (a != b) {
            return false;
        }
        if (b == '{' or b == '}') {
            j += 1;
        }
        j += 1;
    }
    return j == lit.len;
}

fn countEscapes(lit: []const u8) usize {
    var count: usize = 0;
    var i: usize = 0;
    while (i < lit.len) : (i += 1) {
        if (lit[i] == '{' or lit[i] == '}') {
            count += 1;
            i += 1;
        }
    }
    return count;
}

/// Reads from reader into out
/// can not use {b} specifier
/// For more info: https://github.com/DanRyba253/zig-scan/tree/main
pub fn scanOut(
    comptime buf_len: usize,
    comptime fmt: []const u8,
    reader: anytype,
    out: fmt_info.getFmtInfo(fmt).input_type,
) !void {
    if (comptime !interface.hasRelevantReaderMethods(@TypeOf(reader))) {
        @compileError("invalid reader type");
    }

    const info = fmt_info.getFmtInfo(fmt);

    if (comptime fmt_info.capturesSlices(info)) {
        @compileError("can only use {b} with a buffer. Use bufScan or bufScanOut instead");
    }

    const tokens = info.tokens;
    var buf: [buf_len]u8 = undefined;
    var peeker = peek.initPeeker(reader);
    comptime var out_idx = 0;

    inline for (tokens) |token| switch (token) {
        .literal => |literal| {
            const buf_ = buf[0 .. literal.len - countEscapes(literal)];
            try peeker.readNoEof(buf_);
            if (!eqlHandleEscapes(buf_, literal)) {
                return error.LiteralError;
            }
        },
        .fmt_spec => |fmt_spec| switch (fmt_spec) {
            .unicode => {
                buf[0] = peeker.readByte() orelse return error.EOF;

                const byte_count = std.unicode.utf8ByteSequenceLength(buf[0]) catch {
                    return error.UnicodeError;
                };

                for (1..byte_count) |i| {
                    buf[i] = peeker.readByte() orelse return error.EOF;
                }

                const codepoint = std.unicode.utf8Decode(buf[0..byte_count]) catch {
                    return error.UnicodeError;
                };

                out[out_idx].* = codepoint;
                out_idx += 1;
            },
            inline .int, .float => |spec| {
                const is_float = @typeInfo(spec.type) == .Float;
                var expect_dot = is_float;
                var expect_minus = is_float or @typeInfo(spec.type).Int.signedness == .signed;
                var i: usize = 0;

                while (peeker.readByte()) |byte| : (i += 1) {
                    buf[i] = byte;

                    if (byte == '-') {
                        if (expect_minus) {
                            expect_minus = false;
                            continue;
                        } else {
                            peeker.putBack(byte);
                            break;
                        }
                    }
                    expect_minus = false;

                    if (byte == '.') {
                        if (expect_dot) {
                            expect_dot = false;
                            continue;
                        } else {
                            peeker.putBack(byte);
                            break;
                        }
                    }

                    if (byte < '0' or byte > '9') {
                        peeker.putBack(byte);
                        break;
                    }
                }

                const buf_ = buf[0..i];

                if (is_float) {
                    const value = try std.fmt.parseFloat(spec.type, buf_);
                    out[out_idx].* = value;
                    out_idx += 1;
                } else {
                    const value = try std.fmt.parseInt(spec.type, buf_, spec.base);
                    out[out_idx].* = value;
                    out_idx += 1;
                }
            },
            .char => {
                if (peeker.readByte()) |byte| {
                    out[out_idx].* = byte;
                } else {
                    return error.EOF;
                }
                out_idx += 1;
            },
            .string => |spec| {
                var i: usize = 0;

                while (peeker.readByte()) |byte| : (i += 1) {
                    buf[i] = byte;
                    if (spec.terminator == null and std.ascii.isWhitespace(byte)) {
                        peeker.putBack(byte);
                        break;
                    }

                    if (byte == spec.terminator) {
                        break;
                    }
                }

                const buf_ = buf[0..i];

                // asserted that spec.capture_method == .s
                std.mem.copyForwards(u8, out[out_idx].*, buf_);
                out[out_idx].* = out[out_idx].*[0..i];
                out_idx += 1;
            },
            .ws => {
                while (peeker.readByte()) |byte| {
                    if (!std.ascii.isWhitespace(byte)) {
                        peeker.putBack(byte);
                        break;
                    }
                }
            },
        },
    };
}

/// Reads from reader, returns the result
/// can not use {s} or {b} specifiers
/// For more info: https://github.com/DanRyba253/zig-scan/tree/main
pub fn scan(
    comptime buf_len: usize,
    comptime fmt: []const u8,
    reader: anytype,
) !fmt_info.getFmtInfo(fmt).return_type {
    const info = fmt_info.getFmtInfo(fmt);

    if (comptime fmt_info.capturesStringsOrSlices(info)) {
        @compileError("can't use {s} or {b} with scan");
    }

    var out: info.input_type = undefined;
    var result: info.return_type = undefined;

    inline for (&out, &result) |*o, *r| {
        o.* = r;
    }

    try scanOut(buf_len, fmt, reader, out);

    return result;
}

/// Reads from buffer into out
/// For more info: https://github.com/DanRyba253/zig-scan/tree/main
pub fn bufScanOut(
    comptime fmt: []const u8,
    buf: []const u8,
    out: fmt_info.getFmtInfo(fmt).input_type,
) !void {
    const info = fmt_info.getFmtInfo(fmt);

    const tokens = info.tokens;
    comptime var out_idx = 0;
    var buf_ = buf;

    inline for (tokens) |token| switch (token) {
        .literal => |literal| {
            const len = literal.len - countEscapes(literal);
            if (buf_.len < len) {
                return error.LiteralError;
            }
            if (!eqlHandleEscapes(buf_[0..len], literal)) {
                return error.LiteralError;
            }
            buf_ = buf_[len..];
        },
        .fmt_spec => |fmt_spec| switch (fmt_spec) {
            .unicode => {
                if (buf_.len == 0) {
                    return error.EOF;
                }

                const byte_count = std.unicode.utf8ByteSequenceLength(buf_[0]) catch {
                    return error.UnicodeError;
                };

                if (buf_.len < byte_count) {
                    return error.EOF;
                }

                const codepoint = std.unicode.utf8Decode(buf_[0..byte_count]) catch {
                    return error.UnicodeError;
                };

                out[out_idx].* = codepoint;
                out_idx += 1;
                buf_ = buf_[byte_count..];
            },
            inline .int, .float => |spec| {
                const is_float = @typeInfo(spec.type) == .Float;
                var expect_dot = is_float;
                var expect_minus = is_float or @typeInfo(spec.type).Int.signedness == .signed;
                var i: usize = 0;

                while (i < buf_.len) : (i += 1) {
                    if (buf_[i] == '-') {
                        if (expect_minus) {
                            expect_minus = false;
                            continue;
                        } else {
                            break;
                        }
                    }
                    expect_minus = false;

                    if (buf_[i] == '.') {
                        if (expect_dot) {
                            expect_dot = false;
                            continue;
                        } else {
                            break;
                        }
                    }

                    if (buf_[i] < '0' or buf_[i] > '9') {
                        break;
                    }
                }

                if (is_float) {
                    const value = try std.fmt.parseFloat(spec.type, buf_[0..i]);
                    out[out_idx].* = value;
                } else {
                    const value = try std.fmt.parseInt(spec.type, buf_[0..i], spec.base);
                    out[out_idx].* = value;
                }

                out_idx += 1;
                buf_ = buf_[i..];
            },
            .char => {
                if (buf_.len == 0) {
                    return error.EOF;
                }
                out[out_idx].* = buf_[0];
                out_idx += 1;
                buf_ = buf_[1..];
            },
            .string => |spec| {
                var i: usize = 0;
                var found_terminator: bool = false;

                while (i < buf_.len) : (i += 1) {
                    if (spec.terminator == null and std.ascii.isWhitespace(buf_[i])) {
                        break;
                    }

                    if (buf_[i] == spec.terminator) {
                        found_terminator = true;
                        break;
                    }
                }

                switch (spec.capture_method) {
                    .s => {
                        std.mem.copyForwards(u8, out[out_idx].*, buf_[0..i]);
                        out[out_idx].* = out[out_idx].*[0..i];
                    },
                    .b => {
                        out[out_idx].* = buf_[0..i];
                    },
                }

                if (found_terminator) {
                    i += 1;
                }

                out_idx += 1;
                buf_ = buf_[i..];
            },
            .ws => {
                var i: usize = 0;

                while (i < buf_.len) : (i += 1) {
                    if (!std.ascii.isWhitespace(buf_[i])) {
                        break;
                    }
                }

                buf_ = buf_[i..];
            },
        },
    };
}

/// Reads from buffer, returns the result
/// can not use {s} specifier
/// For more info: https://github.com/DanRyba253/zig-scan/tree/main
pub fn bufScan(
    comptime fmt: []const u8,
    buf: []const u8,
) !fmt_info.getFmtInfo(fmt).return_type {
    const info = fmt_info.getFmtInfo(fmt);

    if (comptime fmt_info.capturesStrings(info)) {
        @compileError("can't use {s} with bufScan, consider using bufScanOut instead");
    }

    var out: info.input_type = undefined;
    var result: info.return_type = undefined;

    inline for (&out, &result) |*o, *r| {
        o.* = r;
    }

    try bufScanOut(fmt, buf, out);

    return result;
}

//unit tests

const getFbs = std.io.fixedBufferStream;
const expect = std.testing.expect;
const expectEq = std.testing.expectEqual;
const expectErr = std.testing.expectError;
const expectEqSl = std.testing.expectEqualSlices;

test "scan {i32}" {
    const buf = "123";
    var fbs = getFbs(buf);
    const reader = fbs.reader();

    const r = try scan(1024, "{i32}", reader);

    try expect(@TypeOf(r[0]) == i32);
    try expectEq(r[0], 123);
}

test "scan {i5}" {
    const buf = "12";
    var fbs = getFbs(buf);
    const reader = fbs.reader();

    const r = try scan(1024, "{i5}", reader);

    try expect(@TypeOf(r[0]) == i5);
    try expectEq(r[0], 12);
}

test "scan {u32}" {
    const buf = "123";
    var fbs = getFbs(buf);
    const reader = fbs.reader();

    const r = try scan(1024, "{u32}", reader);

    try expect(@TypeOf(r[0]) == u32);
    try expectEq(r[0], 123);
}

test "scan {u5}" {
    const buf = "12";
    var fbs = getFbs(buf);
    const reader = fbs.reader();

    const r = try scan(1024, "{u5}", reader);

    try expect(@TypeOf(r[0]) == u5);
    try expectEq(12, r[0]);
}

test "scan {i32} negative" {
    const buf = "-123";
    var fbs = getFbs(buf);
    const reader = fbs.reader();

    const r = try scan(1024, "{i32}", reader);

    try expect(@TypeOf(r[0]) == i32);
    try expectEq(-123, r[0]);
}

test "scan {i32:2} negative" {
    const buf = "-10101";
    var fbs = getFbs(buf);
    const reader = fbs.reader();

    const r = try scan(1024, "{i32:2}", reader);

    try expect(@TypeOf(r[0]) == i32);
    try expectEq(-21, r[0]);
}

test "scan {u32} negative expect-error" {
    const buf = "-123";
    var fbs = getFbs(buf);
    const reader = fbs.reader();

    try expectErr(error.InvalidCharacter, scan(1024, "{u32}", reader));
}

test "scan {f16}" {
    const buf = "123";
    var fbs = getFbs(buf);
    const reader = fbs.reader();

    const r = try scan(1024, "{f16}", reader);

    try expect(@TypeOf(r[0]) == f16);
    try expectEq(123.0, r[0]);
}

test "scan {f32}" {
    const buf = "123";
    var fbs = getFbs(buf);
    const reader = fbs.reader();

    const r = try scan(1024, "{f32}", reader);

    try expect(@TypeOf(r[0]) == f32);
    try expectEq(123.0, r[0]);
}

test "scan {f64}" {
    const buf = "123";
    var fbs = getFbs(buf);
    const reader = fbs.reader();

    const r = try scan(1024, "{f64}", reader);

    try expect(@TypeOf(r[0]) == f64);
    try expectEq(123.0, r[0]);
}

test "scan {f16} fractional" {
    const buf = "123.5";
    var fbs = getFbs(buf);
    const reader = fbs.reader();

    const r = try scan(1024, "{f16}", reader);

    try expect(@TypeOf(r[0]) == f16);
    try expectEq(123.5, r[0]);
}

test "scan {f16} negative" {
    const buf = "-123";
    var fbs = getFbs(buf);
    const reader = fbs.reader();

    const r = try scan(1024, "{f16}", reader);

    try expect(@TypeOf(r[0]) == f16);
    try expectEq(-123.0, r[0]);
}

test "scan {c}" {
    const buf = "abc";
    var fbs = getFbs(buf);
    const reader = fbs.reader();

    const r = try scan(1024, "{c}", reader);

    try expect(@TypeOf(r[0]) == u8);
    try expectEq(r[0], 'a');
}

test "scan buf_len" {
    const buf = "123";
    var fbs = getFbs(buf);
    const reader = fbs.reader();

    const r = try scan(3, "{i32}", reader);

    try expect(@TypeOf(r[0]) == i32);
    try expectEq(123, r[0]);
}

test "scan combinations" {
    const buf = "123_25.5__c___-14.0____-5";
    var fbs = getFbs(buf);
    const reader = fbs.reader();

    const r = try scan(1024, "{u32}_{f64}__{c}___{f64}____{i32}", reader);

    try expect(@TypeOf(r[0]) == u32);
    try expect(@TypeOf(r[1]) == f64);
    try expect(@TypeOf(r[2]) == u8);
    try expect(@TypeOf(r[3]) == f64);
    try expect(@TypeOf(r[4]) == i32);

    try expectEq(123, r[0]);
    try expectEq(25.5, r[1]);
    try expectEq('c', r[2]);
    try expectEq(-14.0, r[3]);
    try expectEq(-5, r[4]);
}

test "bufScan {i32}" {
    const buf = "123";
    const r = try bufScan("{i32}", buf);

    try expect(@TypeOf(r[0]) == i32);
    try expectEq(r[0], 123);
}

test "bufScan {i5}" {
    const buf = "12";
    const r = try bufScan("{i5}", buf);

    try expect(@TypeOf(r[0]) == i5);
    try expectEq(r[0], 12);
}

test "bufScan {u32}" {
    const buf = "123";
    const r = try bufScan("{u32}", buf);

    try expect(@TypeOf(r[0]) == u32);
    try expectEq(r[0], 123);
}

test "bufScan {u5}" {
    const buf = "12";
    const r = try bufScan("{u5}", buf);

    try expect(@TypeOf(r[0]) == u5);
    try expectEq(12, r[0]);
}

test "bufScan {i32} negative" {
    const buf = "-123";
    const r = try bufScan("{i32}", buf);

    try expect(@TypeOf(r[0]) == i32);
    try expectEq(-123, r[0]);
}

test "bufScan {i32:2} negative" {
    const buf = "-10101";
    const r = try bufScan("{i32:2}", buf);

    try expect(@TypeOf(r[0]) == i32);
    try expectEq(-21, r[0]);
}

test "bufScan {u32} negative expect-error" {
    const buf = "-123";
    try expectErr(error.InvalidCharacter, bufScan("{u32}", buf));
}

test "bufScan {f16}" {
    const buf = "123";
    const r = try bufScan("{f16}", buf);

    try expect(@TypeOf(r[0]) == f16);
    try expectEq(123.0, r[0]);
}

test "bufScan {f32}" {
    const buf = "123";
    const r = try bufScan("{f32}", buf);

    try expect(@TypeOf(r[0]) == f32);
    try expectEq(123.0, r[0]);
}

test "bufScan {f64}" {
    const buf = "123";
    const r = try bufScan("{f64}", buf);

    try expect(@TypeOf(r[0]) == f64);
    try expectEq(123.0, r[0]);
}

test "bufScan {f16} fractional" {
    const buf = "123.5";
    const r = try bufScan("{f16}", buf);

    try expect(@TypeOf(r[0]) == f16);
    try expectEq(123.5, r[0]);
}

test "bufScan {f16} negative" {
    const buf = "-123";
    const r = try bufScan("{f16}", buf);

    try expect(@TypeOf(r[0]) == f16);
    try expectEq(-123.0, r[0]);
}

test "bufScan {c}" {
    const buf = "abc";
    const r = try bufScan("{c}", buf);

    try expect(@TypeOf(r[0]) == u8);
    try expectEq(r[0], 'a');
}

test "bufScan combinations" {
    const buf = "123_25.5__c___-14.0____-5";
    const r = try bufScan("{u32}_{f64}__{c}___{f64}____{i32}", buf);

    try expect(@TypeOf(r[0]) == u32);
    try expect(@TypeOf(r[1]) == f64);
    try expect(@TypeOf(r[2]) == u8);
    try expect(@TypeOf(r[3]) == f64);
    try expect(@TypeOf(r[4]) == i32);

    try expectEq(123, r[0]);
    try expectEq(25.5, r[1]);
    try expectEq('c', r[2]);
    try expectEq(-14.0, r[3]);
    try expectEq(-5, r[4]);
}

test "scanOut {s}" {
    const buf = "123";
    var fbs = getFbs(buf);
    const reader = fbs.reader();

    var arr: [1024]u8 = undefined;
    var slice: []u8 = &arr;

    try scanOut(1024, "{s}", reader, .{&slice});

    try expectEqSl(u8, "123", slice);
}

test "scanOut {s} padding" {
    const buf = "__123 ***";
    var fbs = getFbs(buf);
    const reader = fbs.reader();

    var arr: [1024]u8 = undefined;
    var slice: []u8 = &arr;

    try scanOut(1024, "__{s} ***", reader, .{&slice});

    try expectEqSl(u8, "123", slice);
}

test "bufScanOut {s}" {
    const buf = "123";

    var arr: [1024]u8 = undefined;
    var slice: []u8 = &arr;

    try bufScanOut("{s}", buf, .{&slice});

    try expectEqSl(u8, "123", slice);
}

test "bufScanOut {s} padding" {
    const buf = "__123 ***";

    var arr: [1024]u8 = undefined;
    var slice: []u8 = &arr;

    try bufScanOut("__{s} ***", buf, .{&slice});

    try expectEqSl(u8, "123", slice);
}

test "bufScanOut {b}" {
    const buf = " 123 ";

    var slice: []u8 = undefined;

    try bufScanOut(" {b} ", buf, .{&slice});

    try expectEqSl(u8, "123", slice);
}

test "bufScan {b}" {
    const buf = "123";

    const r = try bufScan("{b}", buf);

    try expect(@TypeOf(r[0]) == []const u8);
    try expectEqSl(u8, "123", r[0]);
}

test "bufScan {b} padding" {
    const buf = "__123 ***";

    const r = try bufScan("__{b} ***", buf);

    try expect(@TypeOf(r[0]) == []const u8);
    try expectEqSl(u8, "123", r[0]);
}

test "bufScan combinations {s}" {
    const buf = "12_0.5_-2.4_c_name";

    const r = try bufScan("{u8}_{f64}_{f64}_{c}_{b_}", buf);

    try expect(@TypeOf(r[0]) == u8);
    try expect(@TypeOf(r[1]) == f64);
    try expect(@TypeOf(r[2]) == f64);
    try expect(@TypeOf(r[3]) == u8);
    try expect(@TypeOf(r[4]) == []const u8);

    try expectEq(12, r[0]);
    try expectEq(0.5, r[1]);
    try expectEq(-2.4, r[2]);
    try expectEq('c', r[3]);
    try expectEqSl(u8, "name", r[4]);
}

test "scanOut combinations {s}" {
    const buf = "12_0.5_-2.4_c_name_string";
    var fbs = getFbs(buf);
    const reader = fbs.reader();

    var a: u8 = undefined;
    var b: f64 = undefined;
    var c: f64 = undefined;
    var d: u8 = undefined;
    var arr: [1024]u8 = undefined;
    var e: []u8 = &arr;
    var f: []u8 = arr[500..];

    try scanOut(1024, "{u8}_{f64}_{f64}_{c}_{s_}{s}", reader, .{ &a, &b, &c, &d, &e, &f });

    try expectEq(12, a);
    try expectEq(0.5, b);
    try expectEq(-2.4, c);
    try expectEq('c', d);
    try expectEqSl(u8, "name", e);
    try expectEqSl(u8, "string", f);
}

test "bufScanOut combinations {s}" {
    const buf = "12_0.5_-2.4_c_name_string";

    var a: u8 = undefined;
    var b: f64 = undefined;
    var c: f64 = undefined;
    var d: u8 = undefined;
    var arr: [1024]u8 = undefined;
    var e: []u8 = &arr;
    var f: []u8 = undefined;

    try bufScanOut("{u8}_{f64}_{f64}_{c}_{s_}{b_}", buf, .{ &a, &b, &c, &d, &e, &f });

    try expectEq(12, a);
    try expectEq(0.5, b);
    try expectEq(-2.4, c);
    try expectEq('c', d);
    try expectEqSl(u8, "name", e);
    try expectEqSl(u8, "string", f);
}

test "bufScan {{}}" {
    const buf = "}15{";
    const r = try bufScan("}}{i32}{{", buf);

    try expect(@TypeOf(r[0]) == i32);
    try expectEq(15, r[0]);
}

test "bufScan usize" {
    const buf = "15";
    const r = try bufScan("{usize}", buf);

    try expect(@TypeOf(r[0]) == usize);
    try expectEq(15, r[0]);
}

test "bufScan usize base" {
    const buf = "10101";
    const r = try bufScan("{usize:2}", buf);

    try expect(@TypeOf(r[0]) == usize);
    try expectEq(21, r[0]);
}

test "bufScanOut {_}" {
    const buf = "   name";

    var arr: [1024]u8 = undefined;
    var slice: []u8 = &arr;

    try bufScanOut("{_}{b}", buf, .{&slice});

    try expectEqSl(u8, "name", slice);
}

test "scanOut {_}" {
    const buf = "   name";
    var fbs = getFbs(buf);
    const reader = fbs.reader();

    var arr: [1024]u8 = undefined;
    var slice: []u8 = &arr;

    try scanOut(1024, "{_}{s}", reader, .{&slice});

    try expectEqSl(u8, "name", slice);
}

test "scanOut {u} 1" {
    const buf = "\u{40}";
    var fbs = getFbs(buf);
    const reader = fbs.reader();

    var codepoint: u21 = undefined;
    try scanOut(1024, "{u}", reader, .{&codepoint});

    try expectEq(1, try std.unicode.utf8CodepointSequenceLength(codepoint));
    try expectEq(0x40, codepoint);
}

test "scanOut {u} 2" {
    const buf = "\u{80}";
    var fbs = getFbs(buf);
    const reader = fbs.reader();

    var codepoint: u21 = undefined;
    try scanOut(1024, "{u}", reader, .{&codepoint});

    try expectEq(2, try std.unicode.utf8CodepointSequenceLength(codepoint));
    try expectEq(0x80, codepoint);
}

test "scanOut {u} 3" {
    const buf = "\u{800}";
    var fbs = getFbs(buf);
    const reader = fbs.reader();

    var codepoint: u21 = undefined;
    try scanOut(1024, "{u}", reader, .{&codepoint});

    try expectEq(3, try std.unicode.utf8CodepointSequenceLength(codepoint));
    try expectEq(0x800, codepoint);
}

test "scanOut {u} 4" {
    const buf = "\u{10000}";
    var fbs = getFbs(buf);
    const reader = fbs.reader();

    var codepoint: u21 = undefined;
    try scanOut(1024, "{u}", reader, .{&codepoint});

    try expectEq(4, try std.unicode.utf8CodepointSequenceLength(codepoint));
    try expectEq(0x10000, codepoint);
}

test "bufScanOut {u} 1" {
    const buf = "\u{40}";

    var codepoint: u21 = undefined;
    try bufScanOut("{u}", buf, .{&codepoint});

    try expectEq(1, try std.unicode.utf8CodepointSequenceLength(codepoint));
    try expectEq(0x40, codepoint);
}

test "bufScanOut {u} 2" {
    const buf = "\u{80}";

    var codepoint: u21 = undefined;
    try bufScanOut("{u}", buf, .{&codepoint});

    try expectEq(2, try std.unicode.utf8CodepointSequenceLength(codepoint));
    try expectEq(0x80, codepoint);
}

test "bufScanOut {u} 3" {
    const buf = "\u{800}";

    var codepoint: u21 = undefined;
    try bufScanOut("{u}", buf, .{&codepoint});

    try expectEq(3, try std.unicode.utf8CodepointSequenceLength(codepoint));
    try expectEq(0x800, codepoint);
}

test "bufScanOut {u} 4" {
    const buf = "\u{10000}";

    var codepoint: u21 = undefined;
    try bufScanOut("{u}", buf, .{&codepoint});

    try expectEq(4, try std.unicode.utf8CodepointSequenceLength(codepoint));
    try expectEq(0x10000, codepoint);
}
