const std = @import("std");

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = gpa.allocator();
var parsed_args = std.ArrayList(Args.Arg).init(allocator);

pub const Args = struct {
    /// Estructura para almacenar un argumento procesado
    pub const Arg = struct {
        name: ?[:0]const u8,
        value: ?[:0]const u8,
    };

    pub fn init() Args {
        return Args{};
    }
    pub fn deinit(self: *Args) void {
        _ = self;
        // Liberar la memoria de los valores asignados
        // defer {
        for (parsed_args.items) |arg| {
            if (arg.name) |name| allocator.free(name);
            if (arg.value) |value| allocator.free(value);
        }
        parsed_args.deinit();
        // }
    }

    /// Función para procesar los argumentos de línea de comandos
    pub fn parse(self: *Args) !void {
        _ = self;
        parsed_args = std.ArrayList(Arg).init(allocator);
        // Obtener argumentos de línea de comandos
        const args = try std.process.argsAlloc(allocator);
        defer std.process.argsFree(allocator, args);

        var i: usize = 1;
        while (i < args.len) : (i += 1) {
            const arg = args[i];

            // Verificar si es un flag (comienza con - o --)
            if (std.mem.startsWith(u8, arg, "--")) {
                // Flag largo (--flag)
                const label = arg[2..];
                const name: [:0]const u8 = try std.fmt.allocPrintZ(allocator, "{s}\x00", .{label});

                // Verificar si el siguiente argumento es un valor
                if (i + 1 < args.len and !std.mem.startsWith(u8, args[i + 1], "-")) {
                    const value: [:0]const u8 = try std.fmt.allocPrintZ(allocator, "{s}\x00", .{args[i + 1]});
                    try parsed_args.append(Arg{
                        .name = name,
                        .value = value,
                    });
                    i += 1; // Avanzar para saltar el valor
                } else {
                    try parsed_args.append(Arg{
                        .name = name,
                        .value = null,
                    });
                }
            } else if (std.mem.startsWith(u8, arg, "-")) {
                // Flag corto (-f)
                const label = arg[1..];
                const name: [:0]const u8 = try std.fmt.allocPrintZ(allocator, "{s}\x00", .{label});

                // Verificar si el siguiente argumento es un valor
                if (i + 1 < args.len and !std.mem.startsWith(u8, args[i + 1], "-")) {
                    const value = try std.fmt.allocPrintZ(allocator, "{s}\x00", .{args[i + 1]});
                    // std.debug.print("value: {s}\n", .{value});
                    try parsed_args.append(Arg{
                        .name = name,
                        .value = value,
                    });
                    i += 1; // Avanzar para saltar el valor
                } else {
                    std.debug.print("No value\n", .{});
                    try parsed_args.append(Arg{
                        .name = name,
                        .value = null,
                    });
                }
            } else {
                // Argumento posicional (sin flag)
                const value = try std.fmt.allocPrintZ(allocator, "{s}\x00", .{arg});
                try parsed_args.append(Arg{
                    .name = "",
                    .value = value,
                });
            }
        }
        // return parsed_args.toOwnedSlice();
    }

    /// Función para buscar un argumento específico por nombre
    pub fn findArg(name: []const u8) ?*const Arg {
        for (parsed_args.items) |*arg| {
            if (arg.name) |aname| {
                if (std.mem.startsWith(u8, aname, name)) {
                    // if (arg.value) |_| {
                    return arg;
                    // }
                    // return null;
                }
            }
        }
        return null;
    }
};
// Función de ejemplo para demostrar el uso
// pub fn main() !void {
//     var gpa = std.heap.GeneralPurposeAllocator(.{}){};
//     defer _ = gpa.deinit();
//     const allocator = gpa.allocator();
//
//     const stdout = std.io.getStdOut().writer();
//
//     // Analizar argumentos
//     const args = try parseArgs(allocator);
//     defer allocator.free(args);
//
//     // Imprimir todos los argumentos procesados
//     try stdout.writeAll("Argumentos procesados:\n");
//     for (args) |arg| {
//         if (arg.value) |value| {
//             try stdout.print("  {s}: {s}\n", .{ arg.name, value });
//         } else {
//             try stdout.print("  {s} (flag sin valor)\n", .{arg.name});
//         }
//     }
//
//     // Ejemplos de búsqueda de argumentos específicos
//     if (findArg(args, "h") != null or findArg(args, "help") != null) {
//         try stdout.writeAll("\nMostrar ayuda...\n");
//     }
//
//     if (findArg(args, "time")) |time_arg| {
//         if (time_arg.value) |time_str| {
//             const time = try std.fmt.parseFloat(f64, time_str);
//             try stdout.print("\nTiempo especificado: {d:.1} segundos\n", .{time});
//         }
//     }
// }
