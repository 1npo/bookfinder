const std = @import("std");

const Connection = struct {
    stream: std.net.Stream,
    reader: *std.Io.Reader,
    writer: *std.Io.Writer,
    reader_buf: [8192]u8,
    writer_buf: [8192]u8,

    pub fn connect(
        allocator: std.mem.Allocator,
        host: []const u8,
        port: u16,
    ) !Connection {
        const stream = try std.net.tcpConnectToHost(allocator, host, port);
        var conn = Connection{
            .stream = stream,
            .reader = undefined,
            .writer = undefined,
            .reader_buf = undefined,
            .writer_buf = undefined,
        };
        var stream_reader = conn.stream.reader(&conn.reader_buf);
        var stream_writer = conn.stream.writer(&conn.writer_buf);
        conn.reader = stream_reader.interface();
        conn.writer = &stream_writer.interface;
        return conn;
    }

    pub fn disconnect(self: Connection) !void {
        try self.stream.close();
    }

    pub fn sendLine(self: Connection, line: []const u8) !void {
        try self.writer.writeAll(line);
        try self.writer.writeAll("\r\n");
        try self.writer.flush();
        std.debug.print(">>> {s}", .{line});
    }

    pub fn readLine(self: Connection) ![]u8 {
        var line = try self.reader.takeDelimiterInclusive('\n');
        if (line.len >= 1 and line[line.len - 1] == '\r') {
            line = line[0 .. line.len - 1];
        }
        std.debug.print("<<< {s}", .{line});
        return line;
    }
};

pub const IRCBotConfig = struct {
    server_host: []const u8,
    server_port: u16,
    nickname: []const u8,
    username: []const u8,
    realname: []const u8,
    channel: []const u8,
    search_prefix: []const u8,
};

pub const IRCBot = struct {
    config: IRCBotConfig,
    allocator: std.mem.Allocator,
    connection: Connection = undefined,
    is_online: bool = false,
    in_channel: bool = false,

    pub fn connect(allocator: std.mem.Allocator, config: IRCBotConfig) !IRCBot {
        var bot = IRCBot{
            .config = config,
            .allocator = allocator,
            .connection = undefined,
            .is_online = false,
            .in_channel = false,
        };

        bot.connection = try Connection.connect(
            allocator,
            config.server_host,
            config.server_port,
        );

        // Don't try to register until we've received something from the server
        while (true) {
            const line = try bot.connection.readLine();
            if (line.len > 0) break;
            std.Thread.sleep(100 * std.time.ms_per_s);
        }

        try bot.register();

        return bot;
    }

    pub fn register(self: IRCBot) !void {
        const nick_line = try std.fmt.allocPrint(
            self.allocator,
            "{s}{s}",
            .{ "NICK ", self.config.nickname },
        );
        const user_line = try std.fmt.allocPrint(
            self.allocator,
            "{s}{s}{s}{s}",
            .{ "USER ", self.config.username, " 0 * :", self.config.realname },
        );
        try self.connection.sendLine(nick_line);
        try self.connection.sendLine(user_line);
    }

    pub fn logoff(self: *IRCBot) !void {
        try self.connection.disconnect();
    }

    pub fn join(self: IRCBot) !void {
        const line = try std.fmt.allocPrint(
            self.allocator,
            "{s}{s}",
            .{ "JOIN ", self.config.channel },
        );
        try self.connection.sendLine(line);
    }

    pub fn search(self: IRCBot, search_terms: []u8) !void {
        const line = try std.fmt.allocPrint(self.allocator, "{s}{s}{s}{s}{s}{s}", .{
            "PRIVMSG ",
            self.config.channel,
            " :",
            self.config.search_prefix,
            " ",
            search_terms,
        });
        try self.connection.sendLine(line);
    }

    // Typical format is: :Nick!user@host PRIVMSG YourNick :\x01DCC SEND filename
    // ip_as_int port filesize\x01
    pub fn dccGet(self: IRCBot, received_line: []u8) !void {
        if (std.mem.contains(u8, received_line, ":") and std.mem.contains(
            u8,
            received_line,
            "DCC SEND",
        )) {
            _ = self;
        }
    }

    pub fn pong(self: IRCBot, received_line: []u8) !void {
        if (std.mem.startsWith(u8, received_line, "PING ")) {
            const ping = received_line[5..];
            const line = try std.fmt.allocPrint(
                self.allocator,
                "{s}{s}",
                .{ "PONG ", ping },
            );
            try self.connection.sendLine(line);
        }
    }

    pub fn isOnline(self: IRCBot, received_line: []u8) bool {
        _ = self;
        if (std.mem.containsAtLeast(u8, received_line, 1, " 001 ")) {
            return true;
        }
        return false;
    }

    pub fn inChannel(self: IRCBot, received_line: []u8) bool {
        _ = self;
        if (std.mem.containsAtLeast(u8, received_line, 1, " JOIN ")) {
            return true;
        }
        return false;
    }
};
