pub fn Peeker(ReaderType: type) type {
    return struct {
        peeked_value: ?u8,
        reader: ReaderType,

        const Self = @This();

        pub fn init(reader: ReaderType) Self {
            return .{
                .peeked_value = null,
                .reader = reader,
            };
        }

        pub fn readByte(self: *Self) ?u8 {
            if (self.peeked_value) |value| {
                self.peeked_value = null;
                return value;
            } else {
                return self.reader.readByte() catch null;
            }
        }
        pub fn readNoEof(self: *Self, buf: []u8) !void {
            if (buf.len == 0) {
                return;
            }

            if (self.peeked_value) |value| {
                self.peeked_value = null;
                buf[0] = value;
                try self.reader.readNoEof(buf[1..]);
            } else {
                try self.reader.readNoEof(buf);
            }
        }

        pub fn putBack(self: *Self, value: u8) void {
            if (self.peeked_value) |_| {
                @panic("putBack called twice");
            }
            self.peeked_value = value;
        }
    };
}

pub fn initPeeker(reader: anytype) Peeker(@TypeOf(reader)) {
    return Peeker(@TypeOf(reader)).init(reader);
}
