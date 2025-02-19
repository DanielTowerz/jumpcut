const std = @import("std");

const c = @cImport({
    @cInclude("time.h");
});
pub const DateType = struct {
    full: []const u8,
    year: []const u8,
    month: []const u8,
    day: []const u8,
    hour: []const u8,
    minute: []const u8,
    second: []const u8,
    timezone: []const u8,
    pub fn y_m_d(self: *DateType) []const u8 {
        // return self.year ++ self.month ++ self.day;
        return self.full[0..10];
    }
};

pub fn ISO_8601(allocator: std.mem.Allocator) !DateType {
    // Crear un ArrayList para el buffer
    var buffer = std.ArrayList(u8).init(allocator);

    // Reservar espacio en el buffer
    try buffer.resize(64); // Tamaño suficiente para la cadena formateada

    // Obtener el tiempo actual
    const now = c.time(null);
    const timeinfo = c.localtime(&now);

    // Formatear la fecha y hora usando strftime
    const len = c.strftime(buffer.items.ptr, buffer.items.len, "%Y-%m-%d %H:%M:%S %z", timeinfo);
    if (len == 0) {
        return error.FormatFailed;
    }

    // Ajustar el tamaño del buffer al tamaño real de la cadena
    buffer.shrinkAndFree(len);

    // Extraer los campos individuales de la cadena formateada
    const full = try buffer.toOwnedSlice(); // Cadena completa
    const year = full[0..4]; // Año
    const month = full[5..7]; // Mes
    const day = full[8..10]; // Día
    const hour = full[11..13]; // Hora
    const minute = full[14..16]; // Minuto
    const second = full[17..19]; // Segundo
    const timezone = full[20..25]; // Zona horaria

    // Devolver la estructura con los campos
    return .{
        .full = full,
        .year = year,
        .month = month,
        .day = day,
        .hour = hour,
        .minute = minute,
        .second = second,
        .timezone = timezone,
    };
}

// pub fn main() !void {
//     const allocator = std.heap.page_allocator;
//
//     // Llamar a la función ISO_8601
//     const datetime = try ISO_8601(allocator);
//     defer allocator.free(datetime.full); // Liberar la memoria de la cadena completa
//
//     // Imprimir los resultados
//     std.debug.print("Full: {s}\n", .{datetime.full});
//     std.debug.print("Year: {s}\n", .{datetime.year});
//     std.debug.print("Month: {s}\n", .{datetime.month});
//     std.debug.print("Day: {s}\n", .{datetime.day});
//     std.debug.print("Hour: {s}\n", .{datetime.hour});
//     std.debug.print("Minute: {s}\n", .{datetime.minute});
//     std.debug.print("Second: {s}\n", .{datetime.second});
//     std.debug.print("Timezone: {s}\n", .{datetime.timezone});
// }
