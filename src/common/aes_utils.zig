const std = @import("std");
const crypto = std.crypto;
const base64 = std.base64.standard_encoder;
const base64_decoder = std.base64.standard_decoder;
const Allocator = std.mem.Allocator;

pub const AesGcmTool = struct {
    const Self = @This();
    const Gcm = crypto.aead.aes_gcm.Aes256Gcm;
    const NonceSize = Gcm.nonce_length;
    const TagSize = Gcm.tag_length;
    pub const KeySize = Gcm.key_length;

    allocator: ?Allocator = null,
    key: [KeySize]u8,

    /// init by KeySize bytes
    pub fn init(key: [KeySize]u8) Self {
        return .{ .key = key };
    }

    pub fn random_key(allocator: Allocator) !Self {
        var key = try allocator.alloc(u8, KeySize);
        crypto.random.bytes(key);
        const key_slice: *[KeySize]u8 = key[0..KeySize];
        return .{
            .key = key_slice.*,
            .allocator = allocator
        };
    }

    pub fn deinit(self: Self) void {
        if (self.allocator) |a| {
            a.free(self.key);
        }
    }

    /// need free return.
    pub fn encrypt(self: Self, allocator: Allocator, input: []const u8) ![]const u8 {
        var buffer = try allocator.alloc(u8, NonceSize + TagSize + input.len);
        const nonce_buffer: *[NonceSize]u8 = buffer[0..NonceSize];
        const tag_buffer: *[TagSize]u8 = buffer[NonceSize..NonceSize + TagSize];
        const input_buffer = buffer[NonceSize + TagSize..];
        crypto.random.bytes(nonce_buffer);
        Gcm.encrypt(input_buffer, tag_buffer, input, "", nonce_buffer.*, self.key);
        return buffer;
    }

    /// need free return.
    pub fn decrypt(self: Self, allocator: Allocator, encrypted: []u8) ![]u8 {
        const text_len: isize = @intCast(@as(isize, @intCast(encrypted.len)) - @as(isize, @intCast(TagSize)) - @as(isize, @intCast(NonceSize)));
        if (text_len < 0) return error.CiphertextTooShort;

        const nonce_buffer: *[NonceSize]u8 = encrypted[0 .. NonceSize];
        const tag_buffer: *[TagSize]u8 = encrypted[NonceSize .. NonceSize + TagSize];
        const input_buffer = encrypted[NonceSize + TagSize..];

        const output = try allocator.alloc(u8, @intCast(text_len));
        try Gcm.decrypt(output, input_buffer, tag_buffer.*, "", nonce_buffer.*, self.key);
        return output;
    }

    /// need free return.
    pub fn encrypt_to_base64(self: Self, allocator: Allocator, input: []const u8) ![]u8 {
        const bytes = try self.encrypt(allocator, input);
        defer allocator.free(bytes);

        const len = std.base64.standard.Encoder.calcSize(bytes.len);
        const out = try allocator.alloc(u8, len);
        _ = std.base64.standard.Encoder.encode(out, bytes);

        return out;
    }

    /// need free return
    pub fn decrypt_from_base64(self: Self, allocator: Allocator, input: []const u8) ![]u8 {
        const len = try std.base64.standard.Decoder.calcSizeForSlice(input);
        const bytes = try allocator.alloc(u8, len);
        defer allocator.free(bytes);

        try std.base64.standard.Decoder.decode(bytes, input);
        
        return self.decrypt(allocator, bytes);
    }
};

test "AesGcmTool encryption/decryption" {
    const allocator = std.testing.allocator;
    
    const tool = AesGcmTool.random_key(allocator);
    defer tool.deinit();

    const original_text = "hello abc";
    
    const encrypted = try tool.encrypt_to_base64(allocator, original_text);
    defer allocator.free(encrypted);

    const decrypted = try tool.decrypt_from_base64(allocator, encrypted);
    defer allocator.free(decrypted);

    try std.testing.expectEqualStrings(original_text, decrypted);
}