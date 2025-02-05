const std = @import("std");

pub const IntFmtSpec = struct {
    type: type,
    base: u8,
};

pub const FloatFmtSpec = struct {
    type: type,
};

pub const StringCaptureMethod = enum {
    s,
    b,
};

pub const StringFmtSpec = struct {
    terminator: ?u8,
    capture_method: StringCaptureMethod,
};

pub const FmtSpec = union(enum) {
    int: IntFmtSpec,
    float: FloatFmtSpec,
    char,
    string: StringFmtSpec,
    ws,
    unicode,
};

pub const Token = union(enum) {
    literal: []const u8,
    fmt_spec: FmtSpec,
};

pub const FmtInfo = struct {
    return_type: type,
    input_type: type,
    tokens: []Token,
};

pub fn getFmtInfo(comptime fmt: []const u8) FmtInfo {
    @setEvalBranchQuota(20000000);
    comptime var return_types: [1024]type = undefined;
    comptime var return_type_count = 0;

    comptime var input_types: [1024]type = undefined;
    comptime var input_type_count = 0;

    comptime var tokens: [1024]Token = undefined;
    comptime var token_count = 0;

    comptime {
        var i = 0;
        var literal_start = 0;
        while (i < fmt.len) {
            // skip until { or }
            while (i < fmt.len) : (i += 1) {
                switch (fmt[i]) {
                    '{', '}' => break,
                    else => {},
                }
            }

            // Handle {{ and }}
            if (i + 1 < fmt.len and fmt[i + 1] == fmt[i]) {
                i += 2;
                continue;
            }

            // add a new literal token
            if (i > literal_start) {
                const new_literal = fmt[literal_start..i];
                tokens[token_count] = .{ .literal = new_literal };
                token_count += 1;
            }

            if (i >= fmt.len) break;

            if (fmt[i] == '}') {
                @compileError("missing opening {");
            }

            // get past the '{'
            std.debug.assert(fmt[i] == '{');
            i += 1;

            const fmt_begin = i;

            // find closing }
            while (i < fmt.len and fmt[i] != '}') : (i += 1) {}
            const fmt_end = i;

            if (i >= fmt.len) {
                @compileError("missing closing }");
            }

            // get past the '}'
            std.debug.assert(fmt[i] == '}');
            i += 1;
            literal_start = i;

            const fmt_spec = fmt[fmt_begin..fmt_end];

            if (fmt_spec.len == 0) {
                @compileError("empty format specifier");
            }

            //unicode
            if (fmt_spec.len == 1 and fmt_spec[0] == 'u') {
                return_types[return_type_count] = u21;
                return_type_count += 1;

                input_types[input_type_count] = *u21;
                input_type_count += 1;

                tokens[token_count] = .{ .fmt_spec = .unicode };
                token_count += 1;
                continue;
            }

            // usize
            if (std.mem.startsWith(u8, fmt_spec, "usize")) {
                if (fmt_spec.len == 5) {
                    return_types[return_type_count] = usize;
                    return_type_count += 1;

                    input_types[input_type_count] = *usize;
                    input_type_count += 1;

                    tokens[token_count] = .{ .fmt_spec = .{ .int = .{ .type = usize, .base = 10 } } };
                    token_count += 1;
                    continue;
                }

                if (fmt_spec[5] != ':') {
                    @compileError("expected ':' after {usize");
                }

                const base = std.fmt.parseUnsigned(u8, fmt_spec[6..], 10) catch {
                    @compileError("invalid base for {usize} specifier");
                };

                return_types[return_type_count] = usize;
                return_type_count += 1;

                input_types[input_type_count] = *usize;
                input_type_count += 1;

                tokens[token_count] = .{ .fmt_spec = .{ .int = .{ .type = usize, .base = base } } };
                token_count += 1;
                continue;
            }

            // ints
            if (fmt_spec[0] == 'i' or fmt_spec[0] == 'u') {
                const signedness = if (fmt_spec[0] == 'i') .signed else .unsigned;

                const m_colon_idx = std.mem.indexOfScalar(u8, fmt_spec, ':');
                var base = 10;
                var bits_str: []const u8 = fmt_spec[1..];

                if (m_colon_idx) |idx| {
                    base = std.fmt.parseUnsigned(u8, fmt_spec[idx + 1 ..], 10) catch {
                        @compileError("invalid base for {i} or {u} specifier");
                    };
                    bits_str = fmt_spec[1..idx];
                }

                const bits = std.fmt.parseUnsigned(u16, bits_str, 10) catch {
                    @compileError("invalid bit count for {i} or {u} specifier");
                };
                const new_type = std.meta.Int(signedness, bits);
                return_types[return_type_count] = new_type;
                return_type_count += 1;

                input_types[input_type_count] = *new_type;
                input_type_count += 1;

                tokens[token_count] = .{ .fmt_spec = .{ .int = .{ .type = new_type, .base = base } } };
                token_count += 1;
                continue;
            }

            //floats
            if (fmt_spec[0] == 'f') {
                const bits = std.fmt.parseUnsigned(u8, fmt_spec[1..], 10) catch {
                    @compileError("invalid bit count for {f} specifier");
                };

                if (bits != 16 and bits != 32 and bits != 64) {
                    @compileError("invalid bit count for {f} specifier");
                }

                const new_type = std.meta.Float(bits);
                return_types[return_type_count] = new_type;
                return_type_count += 1;

                input_types[input_type_count] = *new_type;
                input_type_count += 1;

                tokens[token_count] = .{ .fmt_spec = .{ .float = .{ .type = new_type } } };
                token_count += 1;
                continue;
            }

            // chars
            if (fmt_spec.len == 1 and fmt_spec[0] == 'c') {
                return_types[return_type_count] = u8;
                return_type_count += 1;

                input_types[input_type_count] = *u8;
                input_type_count += 1;

                tokens[token_count] = .{ .fmt_spec = .char };
                token_count += 1;
                continue;
            }

            //strings
            if (fmt_spec[0] == 's') {
                const len = fmt_spec.len;
                if (len > 2) {
                    @compileError("{s} specifer can be at most 2 characters");
                }

                const terminator = if (len == 2)
                    fmt_spec[1]
                else
                    null;

                return_types[return_type_count] = void;
                return_type_count += 1;

                input_types[input_type_count] = *[]u8;
                input_type_count += 1;

                tokens[token_count] = .{ .fmt_spec = .{ .string = .{ .terminator = terminator, .capture_method = .s } } };
                token_count += 1;
                continue;
            }

            if (fmt_spec[0] == 'b') {
                const len = fmt_spec.len;
                if (len > 2) {
                    @compileError("{b} specifier can be at most 2 characters");
                }

                const terminator = if (len == 2)
                    fmt_spec[1]
                else
                    null;

                return_types[return_type_count] = []const u8;
                return_type_count += 1;

                input_types[input_type_count] = *[]const u8;
                input_type_count += 1;

                tokens[token_count] = .{ .fmt_spec = .{ .string = .{ .terminator = terminator, .capture_method = .b } } };
                token_count += 1;
                continue;
            }

            // whitespace
            if (fmt_spec.len == 1 and fmt_spec[0] == '_') {
                tokens[token_count] = .{ .fmt_spec = .ws };
                token_count += 1;
                continue;
            }

            @compileError("invalid format specifier");
        }
    }

    return FmtInfo{
        .return_type = std.meta.Tuple(return_types[0..return_type_count]),
        .input_type = std.meta.Tuple(input_types[0..input_type_count]),
        .tokens = tokens[0..token_count],
    };
}

pub fn capturesSlices(info: FmtInfo) bool {
    comptime var result: bool = false;

    comptime {
        for (info.tokens) |token| switch (token) {
            .fmt_spec => |fmt_spec| switch (fmt_spec) {
                .string => |spec| {
                    if (spec.capture_method == .b) {
                        result = true;
                    }
                },
                else => {},
            },
            else => {},
        };
    }

    return result;
}

pub fn capturesStringsOrSlices(info: FmtInfo) bool {
    comptime var result: bool = false;

    comptime {
        for (info.tokens) |token| switch (token) {
            .fmt_spec => |fmt_spec| switch (fmt_spec) {
                .string => {
                    result = true;
                },
                else => {},
            },
            else => {},
        };
    }

    return result;
}

pub fn capturesStrings(info: FmtInfo) bool {
    comptime var result: bool = false;

    comptime {
        for (info.tokens) |token| switch (token) {
            .fmt_spec => |fmt_spec| switch (fmt_spec) {
                .string => |spec| {
                    if (spec.capture_method == .s) {
                        result = true;
                    }
                },
                else => {},
            },
            else => {},
        };
    }

    return result;
}
