enum PrinterConnectionType { network, bluetooth }

class PrinterSettings {
  final PrinterConnectionType connectionType;
  // Máy in bếp (Kitchen Ticket)
  final bool kitchenEnabled;
  final String ipAddress;
  final int port;
  // Máy in lễ tân (Bill Ticket)
  final bool billEnabled;
  final String billIpAddress;
  final int billPort;
  // Paper
  final int paperWidth; // 58 or 80 mm
  // Encoding
  final bool unicodeVietnamese;

  const PrinterSettings({
    this.connectionType = PrinterConnectionType.network,
    this.kitchenEnabled = true,
    this.ipAddress = '192.168.1.100',
    this.port = 9100,
    this.billEnabled = true,
    this.billIpAddress = '192.168.1.101',
    this.billPort = 9100,
    this.paperWidth = 80,
    this.unicodeVietnamese = false,
  });

  PrinterSettings copyWith({
    PrinterConnectionType? connectionType,
    bool? kitchenEnabled,
    String? ipAddress,
    int? port,
    bool? billEnabled,
    String? billIpAddress,
    int? billPort,
    int? paperWidth,
    bool? unicodeVietnamese,
  }) => PrinterSettings(
    connectionType: connectionType ?? this.connectionType,
    kitchenEnabled: kitchenEnabled ?? this.kitchenEnabled,
    ipAddress: ipAddress ?? this.ipAddress,
    port: port ?? this.port,
    billEnabled: billEnabled ?? this.billEnabled,
    billIpAddress: billIpAddress ?? this.billIpAddress,
    billPort: billPort ?? this.billPort,
    paperWidth: paperWidth ?? this.paperWidth,
    unicodeVietnamese: unicodeVietnamese ?? this.unicodeVietnamese,
  );
}
