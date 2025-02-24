const std = @import("std");

fn truncfloat(x: f64) f64 {
    return @as(f64, @trunc(x * 100)) / 100;
}

fn gcd(a: u64, b: u64) u64 {
    return if (b == 0) a else gcd(b, a % b);
}

pub fn findDenominator(x: f64) struct { numerator: u64, denominator: u64 } {
    const x_trunc = truncfloat(x);
    // std.debug.print("Truncado: {d}\n", .{x_trunc});
    var numerador: u64 = @as(u64, @intFromFloat(x_trunc * 1_000_000_000)); // Asegurar precisión
    var denominador: u64 = 1_000_000_000;
    // std.debug.print("1Denominador: {d}\n", .{denominador});

    const divisor = gcd(@intCast(numerador), denominador);
    numerador = numerador / divisor;
    // std.debug.print("2Divisor: {d}\n", .{divisor});
    denominador = denominador / divisor; // Retornar el denominador mínimo
    // std.debug.print("Denominador: {d}\n", .{denominador});
    if (denominador < 100) {
        denominador *= 100;
    }
    while (denominador > numerador) {
        if (numerador == 0) {
            break;
        }
        numerador *= 100;
        // std.debug.print("Numerador: {d}, Denominador: {d}\n", .{ numerador, denominador });
        // denominador *= 100;
    }
    // std.debug.print("3Denominador: {d}\n", .{denominador});
    // numerador = numerador * denominador;
    return .{ .numerator = numerador, .denominator = denominador };
}
