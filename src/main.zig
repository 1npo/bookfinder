const std = @import("std");
const irc = @import("irc.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena.deinit();

    const allocator = arena.allocator();

    const config = irc.IRCBotConfig{
        .server_host = "irc.undernet.org",
        .server_port = 6667,
        .nickname = "bookfinder",
        .username = "bookfinder",
        .realname = "bookfinder",
        .channel = "#bookz",
        .search_prefix = "@search",
    };

    var bot = try irc.IRCBot.connect(allocator, config);

    while (true) {
        const line = try bot.connection.readLine();

        try bot.pong(line);

        if (!bot.is_online) {
            if (bot.isOnline(line)) {
                bot.is_online = true;
            }
        }
        if (!bot.in_channel) {
            if (bot.inChannel(line)) {
                bot.in_channel = true;
            }
        }

        if (bot.is_online and !bot.in_channel) {
            try bot.join();
            // bot.search("leviathan wakes james corey");
        }
    }

    try bot.logoff();
}
