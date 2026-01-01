const std = @import("std");
const crypto = std.crypto;
const Allocator = std.mem.Allocator;

pub const AesGcmTool = struct {
    const Self = @This();
    const Gcm = crypto.aead.aes_gcm.Aes256Gcm;
    const NonceSize = Gcm.nonce_length;
    const TagSize = Gcm.tag_length;
    pub const KeySize = Gcm.key_length;

    key: [KeySize]u8,

    /// init by KeySize bytes
    pub fn init(key: [KeySize]u8) Self {
        return .{ .key = key };
    }

    pub fn random_key() Self {
        var key: [KeySize]u8 = undefined;
        crypto.random.bytes(&key);
        return .{
            .key = key,
        };
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

        const len = std.base64.url_safe.Encoder.calcSize(bytes.len);
        const out = try allocator.alloc(u8, len);
        _ = std.base64.url_safe.Encoder.encode(out, bytes);

        return out;
    }

    pub fn encrypt_model_to_base64(self: Self, comptime T: type, allocator: Allocator, input: T) ![]u8 {
        const formatter = std.json.fmt(input, .{ .emit_null_optional_fields = false });
        const json = try std.fmt.allocPrint(allocator, "{f}", .{formatter});
        defer allocator.free(json);
        return self.encrypt_to_base64(allocator, json);
    }

    /// need free return
    pub fn decrypt_from_base64(self: Self, allocator: Allocator, input: []const u8) ![]u8 {
        const len = try std.base64.url_safe.Decoder.calcSizeForSlice(input);
        const bytes = try allocator.alloc(u8, len);
        defer allocator.free(bytes);

        try std.base64.url_safe.Decoder.decode(bytes, input);
        
        return self.decrypt(allocator, bytes);
    }
    
    pub fn decrypt_model_to_base64(self: Self, comptime T: type, allocator: Allocator, input: []const u8) !std.json.Parsed(T) {
        const json = try self.decrypt_from_base64(allocator, input);
        defer allocator.free(json);
        return try std.json.parseFromSlice(T, allocator, json, .{ .ignore_unknown_fields = true });
    }
};

test "AesGcmTool encryption/decryption" {
    const allocator = std.testing.allocator;
    
    const tool = AesGcmTool.random_key();

    const original_text = "hello abc";
    
    const encrypted = try tool.encrypt_to_base64(allocator, original_text);
    defer allocator.free(encrypted);

    const decrypted = try tool.decrypt_from_base64(allocator, encrypted);
    defer allocator.free(decrypted);

    try std.testing.expectEqualStrings(original_text, decrypted);
}