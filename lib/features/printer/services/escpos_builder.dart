import 'dart:convert';
import 'dart:typed_data';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import '../models/bill_model.dart';
import '../models/kitchen_ticket_model.dart';
import '../models/printer_settings.dart';

/// Builds ESC/POS byte commands from a Bill object.
class EscPosBuilder {
  /// Layer 1 — Bảng ánh xạ 1-1 dễ đọc: Unicode tiếng Việt → ký tự thay thế (1 char).
  ///
  /// Key   : ký tự Unicode gốc (ví dụ: 'ừ', 'ổ', 'ắ')
  /// Value : ký tự thay thế tốt nhất có trong PC850 (ví dụ: 'ù', 'ô', 'á')
  ///         hoặc ASCII gốc nếu không có xấp xỉ nào phù hợp ('d' cho 'đ').
  ///
  /// Nguyên tắc xấp xỉ cho ký tự không có trong PC850:
  ///   ă-series : giữ dấu thanh nếu có (ắ→á, ằ→à), bỏ dấu mũ ă.
  ///   ơ-series : giữ dấu thanh nếu có (ớ→ó, ờ→ò), bỏ dấu mũ ơ.
  ///   ư-series : giữ dấu thanh nếu có (ứ→ú, ừ→ù), bỏ dấu mũ ư.
  ///   đ        : → 'd' / 'D'.
  static Map<String, String> get pc850Map => {
    // ── a thường ──────────────────────────────────────────────────────
    'à': 'à',  // huyền  → à (PC850 0x85)
    'á': 'á',  // sắc    → á (PC850 0xA0)
    'â': 'â',  // mũ     → â (PC850 0x83)
    'ã': 'ã',  // ngã    → ã (PC850 0xC6)
    'ả': 'a',  // hỏi    → a
    'ạ': 'a',  // nặng   → a
    // â + dấu → giữ nguyên â (mất dấu thanh)
    'ầ': 'â', 'ấ': 'â', 'ẩ': 'â', 'ẫ': 'â', 'ậ': 'â',
    // ă + dấu → giữ dấu thanh, bỏ ă
    'ă': 'a',
    'ằ': 'à',  // ă huyền → à  ✓
    'ắ': 'á',  // ă sắc   → á  ✓
    'ẳ': 'a',  // ă hỏi   → a
    'ẵ': 'a',  // ă ngã   → a
    'ặ': 'a',  // ă nặng  → a

    // ── A hoa ─────────────────────────────────────────────────────────
    'À': 'À',  // PC850 0xB7
    'Á': 'Á',  // PC850 0xB5
    'Â': 'Â',  // PC850 0xB6
    'Ã': 'Ã',  // PC850 0xC7
    'Ả': 'A', 'Ạ': 'A',
    'Ầ': 'Â', 'Ấ': 'Â', 'Ẩ': 'Â', 'Ẫ': 'Â', 'Ậ': 'Â',
    'Ă': 'A',
    'Ằ': 'À', 'Ắ': 'Á', 'Ẳ': 'A', 'Ẵ': 'A', 'Ặ': 'A',

    // ── e thường ──────────────────────────────────────────────────────
    'è': 'è',  // huyền  → è (PC850 0x8A)
    'é': 'é',  // sắc    → é (PC850 0x82)
    'ê': 'ê',  // mũ     → ê (PC850 0x88)
    'ẻ': 'e', 'ẽ': 'e', 'ẹ': 'e',
    // ê + dấu → giữ nguyên ê
    'ề': 'ê', 'ế': 'ê', 'ể': 'ê', 'ễ': 'ê', 'ệ': 'ê',

    // ── E hoa ─────────────────────────────────────────────────────────
    'È': 'È',  // PC850 0xD4
    'É': 'É',  // PC850 0x90
    'Ê': 'Ê',  // PC850 0xD2
    'Ẻ': 'E', 'Ẽ': 'E', 'Ẹ': 'E',
    'Ề': 'Ê', 'Ế': 'Ê', 'Ể': 'Ê', 'Ễ': 'Ê', 'Ệ': 'Ê',

    // ── i thường ──────────────────────────────────────────────────────
    'ì': 'ì',  // huyền  → ì (PC850 0x8D)
    'í': 'í',  // sắc    → í (PC850 0xA1)
    'ỉ': 'i', 'ĩ': 'i', 'ị': 'i',

    // ── I hoa ─────────────────────────────────────────────────────────
    'Ì': 'Ì',  // PC850 0xDE
    'Í': 'Í',  // PC850 0xD6
    'Ỉ': 'I', 'Ĩ': 'I', 'Ị': 'I',

    // ── o thường ──────────────────────────────────────────────────────
    'ò': 'ò',  // huyền  → ò (PC850 0x95)
    'ó': 'ó',  // sắc    → ó (PC850 0xA2)
    'ô': 'ô',  // mũ     → ô (PC850 0x93)
    'õ': 'õ',  // ngã    → õ (PC850 0xE4)
    'ỏ': 'o', 'ọ': 'o',
    // ô + dấu → giữ nguyên ô
    'ồ': 'ô', 'ố': 'ô', 'ổ': 'ô', 'ỗ': 'ô', 'ộ': 'ô',
    // ơ + dấu → giữ dấu thanh, bỏ ơ
    'ơ': 'o',
    'ờ': 'ò',  // ơ huyền → ò  ✓
    'ớ': 'ó',  // ơ sắc   → ó  ✓
    'ở': 'o',  // ơ hỏi   → o
    'ỡ': 'o',  // ơ ngã   → o
    'ợ': 'o',  // ơ nặng  → o

    // ── O hoa ─────────────────────────────────────────────────────────
    'Ò': 'Ò',  // PC850 0xE3
    'Ó': 'Ó',  // PC850 0xE0
    'Ô': 'Ô',  // PC850 0xE2
    'Õ': 'Õ',  // PC850 0xE5
    'Ỏ': 'O', 'Ọ': 'O',
    'Ồ': 'Ô', 'Ố': 'Ô', 'Ổ': 'Ô', 'Ỗ': 'Ô', 'Ộ': 'Ô',
    'Ơ': 'O',
    'Ờ': 'Ò', 'Ớ': 'Ó', 'Ở': 'O', 'Ỡ': 'O', 'Ợ': 'O',

    // ── u thường ──────────────────────────────────────────────────────
    'ù': 'ù',  // huyền  → ù (PC850 0x97)
    'ú': 'ú',  // sắc    → ú (PC850 0xA3)
    'û': 'û',  // mũ     → û (PC850 0x96)
    'ủ': 'u', 'ũ': 'u', 'ụ': 'u',
    // ư + dấu → giữ dấu thanh, bỏ ư
    'ư': 'u',
    'ừ': 'ù',  // ư huyền → ù  ✓
    'ứ': 'ú',  // ư sắc   → ú  ✓
    'ử': 'u',  // ư hỏi   → u
    'ữ': 'u',  // ư ngã   → u
    'ự': 'u',  // ư nặng  → u

    // ── U hoa ─────────────────────────────────────────────────────────
    'Ù': 'Ù',  // PC850 0xEB
    'Ú': 'Ú',  // PC850 0xE9
    'Û': 'Û',  // PC850 0xEA
    'Ủ': 'U', 'Ũ': 'U', 'Ụ': 'U',
    'Ư': 'U',
    'Ừ': 'Ù', 'Ứ': 'Ú', 'Ử': 'U', 'Ữ': 'U', 'Ự': 'U',

    // ── y thường ──────────────────────────────────────────────────────
    'ý': 'ý',  // sắc    → ý (PC850 0xEC)
    'ỳ': 'y', 'ỷ': 'y', 'ỹ': 'y', 'ỵ': 'y',

    // ── Y hoa ─────────────────────────────────────────────────────────
    'Ý': 'Ý',  // PC850 0xED
    'Ỳ': 'Y', 'Ỷ': 'Y', 'Ỹ': 'Y', 'Ỵ': 'Y',

    // ── đ / Đ ─────────────────────────────────────────────────────────
    'đ': 'd',  // → 'd'
    'Đ': 'D',  // → 'D'
  };

  /// Layer 2 — Byte PC850 cho các ký tự Latin mở rộng có trong PC850.
  /// (Các ký tự ASCII 0–127 giữ nguyên byte value, không cần tra bảng này.)
  static const _pc850Bytes = <String, int>{
    'à': 133, 'á': 160, 'â': 131, 'ã': 198,
    'è': 138, 'é': 130, 'ê': 136,
    'ì': 141, 'í': 161,
    'ò': 149, 'ó': 162, 'ô': 147, 'õ': 228,
    'ù': 151, 'ú': 163, 'û': 150,
    'ý': 236,
    'À': 183, 'Á': 181, 'Â': 182, 'Ã': 199,
    'È': 212, 'É': 144, 'Ê': 210,
    'Ì': 222, 'Í': 214,
    'Ò': 227, 'Ó': 224, 'Ô': 226, 'Õ': 229,
    'Ù': 235, 'Ú': 233, 'Û': 234,
    'Ý': 237,
  };

  /// Encode chuỗi Unicode → bytes PC850 qua 2 bước:
  ///   1. [pc850Map]   : Unicode char → ký tự thay thế tốt nhất
  ///   2. [_pc850Bytes]: ký tự thay thế → byte PC850 thực tế
  static Uint8List _enc(String text) {
    final charMap = pc850Map;
    final result = <int>[];
    for (var i = 0; i < text.length; i++) {
      final c = text[i];
      final replacement = charMap[c] ?? c;          // bước 1
      final byte = _pc850Bytes[replacement]          // bước 2
          ?? (replacement.codeUnitAt(0) < 128
              ? replacement.codeUnitAt(0)
              : 0x3F);
      result.add(byte);
    }
    return Uint8List.fromList(result);
  }
  static Future<List<int>> buildBill(
    Bill bill,
    PrinterSettings settings,
  ) async {
    final profile = await CapabilityProfile.load();
    final effectivePaperWidth = bill.paperWidth ?? settings.paperWidth;
    final paperSize =
        effectivePaperWidth == 80 ? PaperSize.mm80 : PaperSize.mm58;
    final generator = Generator(paperSize, profile);
    final unicode = settings.unicodeVietnamese;

    // Encode text → bytes theo loại máy in
    Uint8List eb(String s) => unicode
        ? Uint8List.fromList(utf8.encode(s))
        : _enc(s);

    List<int> bytes = [];

    if (unicode) {
      // UTF-8 mode (ESC t 255 hoặc lệnh đặc biệt tuỳ máy — bỏ qua ESC t)
    } else {
      // PC850 (ESC t 2)
      bytes += [0x1B, 0x74, 0x02];
    }

    // ── Header ──────────────────────────────────────────────────
    bytes += generator.textEncoded(
      eb(bill.shopName),
      styles: const PosStyles(
        bold: true,
        align: PosAlign.center,
        height: PosTextSize.size2,
        width: PosTextSize.size2,
      ),
    );

    if (bill.shopAddress != null && bill.shopAddress!.isNotEmpty) {
      bytes += generator.textEncoded(
        eb(bill.shopAddress!),
        styles: const PosStyles(align: PosAlign.center),
      );
    }

    if (bill.shopPhone != null && bill.shopPhone!.isNotEmpty) {
      bytes += generator.textEncoded(
        eb('DT: ${bill.shopPhone!}'),
        styles: const PosStyles(align: PosAlign.center),
      );
    }

    bytes += generator.textEncoded(
      eb('HÓA ĐƠN BÁN HÀNG'),
      styles: const PosStyles(
        bold: true,
        align: PosAlign.center,
        height: PosTextSize.size1,
        width: PosTextSize.size1,
      ),
    );

    final timeStr =
        DateFormat('dd/MM/yyyy HH:mm').format(bill.printTime);
    bytes += generator.textEncoded(
      eb('In lúc: $timeStr'),
      styles: const PosStyles(align: PosAlign.center),
    );

    bytes += generator.hr();

    // ── Info ────────────────────────────────────────────────────
    bytes += generator.textEncoded(eb('Nhân viên: ${bill.staffName}'));
    bytes += generator.textEncoded(eb('Khách hàng: ${bill.customerName}'));
    bytes += generator.textEncoded(eb('Bàn: ${bill.tableNumber}'));

    bytes += generator.hr();

    // ── Column header ───────────────────────────────────────────
    final colWidths = _columnWidths(effectivePaperWidth);
    bytes += generator.row([
      PosColumn(
        textEncoded: eb('Mặt hàng'),
        width: colWidths[0],
        styles: const PosStyles(bold: true),
      ),
      PosColumn(
        text: 'SL',
        width: colWidths[1],
        styles: const PosStyles(bold: true, align: PosAlign.center),
      ),
      PosColumn(
        textEncoded: eb('T.Tiền'),
        width: colWidths[2],
        styles: const PosStyles(bold: true, align: PosAlign.right),
      ),
    ]);

    bytes += generator.hr(ch: '-');

    // ── Items ───────────────────────────────────────────────────
    final numFmt = NumberFormat('#,###', 'vi_VN');
    final groupedItems = _groupBillItems(bill.items);
    final lightHr = (effectivePaperWidth == 80 ? '- ' * 24 : '- ' * 16).trimRight();
    for (var idx = 0; idx < groupedItems.length; idx++) {
      final item = groupedItems[idx];
      final totalStr = numFmt.format(item.total.toInt());
      final unitPriceStr = numFmt.format(item.unitPrice.toInt());
      final nameMaxLen = _nameMaxLen(effectivePaperWidth);
      final wrappedLines = _wrapText(item.displayName, nameMaxLen);

      // Print all lines except the last as standalone text
      for (var i = 0; i < wrappedLines.length - 1; i++) {
        bytes += generator.textEncoded(eb(wrappedLines[i]));
      }

      // Last name line + qty + total in row
      bytes += generator.row([
        PosColumn(
          textEncoded: eb(wrappedLines.last),
          width: colWidths[0],
        ),
        PosColumn(
          text: '${item.quantity}',
          width: colWidths[1],
          styles: const PosStyles(align: PosAlign.center),
        ),
        PosColumn(
          text: totalStr,
          width: colWidths[2],
          styles: const PosStyles(align: PosAlign.right),
        ),
      ]);

      // Unit price line
      bytes += generator.textEncoded(eb('  Đơn giá: $unitPriceStr'));

      // Light separator between items (not after the last one)
      if (idx < groupedItems.length - 1) {
        bytes += generator.textEncoded(eb(lightHr));
      }
    }

    bytes += generator.hr();

    // ── Note ────────────────────────────────────────────────────
    if (bill.note.isNotEmpty) {
      bytes += generator.textEncoded(eb('Ghi chú: ${bill.note}'));
    }

    // ── Adjustment ──────────────────────────────────────────────
    if (bill.adjustment != 0) {
      final adjLabel = bill.adjustNote.isNotEmpty
          ? bill.adjustNote
          : (bill.adjustment > 0 ? 'Phụ thu' : 'Giảm giá');
      final adjStr =
          '${bill.adjustment > 0 ? '+' : ''}${numFmt.format(bill.adjustment.toInt())}';
      bytes += generator.row([
        PosColumn(textEncoded: eb(adjLabel), width: 8),
        PosColumn(
          text: adjStr,
          width: 4,
          styles: const PosStyles(align: PosAlign.right),
        ),
      ]);
    }

    // ── Total ───────────────────────────────────────────────────
    final totalStr = numFmt.format(bill.finalTotal.toInt());
    bytes += generator.row([
      PosColumn(
        textEncoded: eb('Tổng:'),
        width: 8,
        styles: const PosStyles(
          bold: true,
          height: PosTextSize.size2,
          width: PosTextSize.size1,
        ),
      ),
      PosColumn(
        text: totalStr,
        width: 4,
        styles: const PosStyles(
          bold: true,
          align: PosAlign.right,
          height: PosTextSize.size2,
          width: PosTextSize.size1,
        ),
      ),
    ]);

    bytes += generator.hr();

    // ── Bank info ───────────────────────────────────────────────
    final hasBankInfo = (bill.bankName != null && bill.bankName!.isNotEmpty) ||
        (bill.bankAccountNumber != null && bill.bankAccountNumber!.isNotEmpty) ||
        (bill.bankAccountName != null && bill.bankAccountName!.isNotEmpty) ||
        (bill.bankQrUrl != null && bill.bankQrUrl!.isNotEmpty);

    if (hasBankInfo) {
      bytes += generator.textEncoded(
        eb('--- Chuyen khoan ngan hang ---'),
        styles: const PosStyles(align: PosAlign.center, bold: true),
      );
      // QR code image
      if (bill.bankQrUrl != null && bill.bankQrUrl!.isNotEmpty) {
        final qrImage = await _downloadImage(bill.bankQrUrl!);
        if (qrImage != null) {
          final printWidth = effectivePaperWidth == 80 ? 480 : 200;
          final resized = img.copyResize(qrImage, width: printWidth, height: printWidth);
          bytes += generator.image(resized, align: PosAlign.center);
        }
      }
      bytes += generator.hr();
    }

    // ── Footer ──────────────────────────────────────────────────
    bytes += generator.textEncoded(
      eb(bill.footer),
      styles: const PosStyles(align: PosAlign.center),
    );
    bytes += generator.feed(1);
    bytes += generator.cut();

    return bytes;
  }

  static Future<List<int>> buildKitchenTicket(
    KitchenTicket ticket,
    PrinterSettings settings,
  ) async {
    final profile = await CapabilityProfile.load();
    final effectivePaperWidth = ticket.paperWidth ?? settings.paperWidth;
    final paperSize =
        effectivePaperWidth == 80 ? PaperSize.mm80 : PaperSize.mm58;
    final generator = Generator(paperSize, profile);
    final unicode = settings.unicodeVietnamese;

    Uint8List eb(String s) => unicode
        ? Uint8List.fromList(utf8.encode(s))
        : _enc(s);

    List<int> bytes = [];

    if (!unicode) {
      bytes += [0x1B, 0x74, 0x02]; // PC850
    }

    // ── Header ──────────────────────────────────────────────────
    bytes += generator.textEncoded(
      eb('CHẾ BIẾN'),
      styles: const PosStyles(
        bold: true,
        align: PosAlign.center,
        height: PosTextSize.size2,
        width: PosTextSize.size2,
      ),
    );
    bytes += generator.textEncoded(
      eb('(Bếp)'),
      styles: const PosStyles(align: PosAlign.center),
    );

    // ── Info ────────────────────────────────────────────────────
    final timeFmt = DateFormat('dd/MM/yyyy HH:mm');
    final timeStr = timeFmt.format(ticket.orderTime);

    // Order ID + datetime on same row
    final colW = effectivePaperWidth == 80 ? [6, 6] : [5, 7];
    bytes += generator.row([
      PosColumn(
        textEncoded: eb('Order: #${ticket.orderId}'),
        width: colW[0],
        styles: const PosStyles(bold: true),
      ),
      PosColumn(
        textEncoded: eb('Ngày: $timeStr'),
        width: colW[1],
        styles: const PosStyles(align: PosAlign.right),
      ),
    ]);

    bytes += generator.textEncoded(eb('Bàn: ${ticket.tableNumber}'));

    if (ticket.staffName.isNotEmpty) {
      bytes += generator.textEncoded(eb('NV: ${ticket.staffName}'));
    }

    bytes += generator.hr();

    // ── Column header ───────────────────────────────────────────
    final kColWidths = _kitchenColumnWidths(effectivePaperWidth);
    bytes += generator.row([
      PosColumn(
        textEncoded: eb('Món'),
        width: kColWidths[0],
        styles: const PosStyles(bold: true),
      ),
      PosColumn(
        text: 'Size',
        width: kColWidths[1],
        styles: const PosStyles(bold: true, align: PosAlign.center),
      ),
      PosColumn(
        text: 'SL',
        width: kColWidths[2],
        styles: const PosStyles(bold: true, align: PosAlign.center),
      ),
    ]);
    bytes += generator.hr(ch: '-');

    // ── Items ───────────────────────────────────────────────────
    final kLightHr = (effectivePaperWidth == 80 ? '- ' * 24 : '- ' * 16).trimRight();
    for (var idx = 0; idx < ticket.items.length; idx++) {
      final item = ticket.items[idx];
      final nameRaw = item.name + (item.isTakeaway ? ' [Mang ve]' : '');
      final sizeStr = item.sizeName ?? '';
      final qtyStr = '${item.quantity}';

      final nameMaxLen = effectivePaperWidth == 80 ? 22 : 14;
      final wrappedLines = _wrapText(nameRaw, nameMaxLen);

      // Dòng đầu tiên: tên + size + qty
      bytes += generator.row([
        PosColumn(textEncoded: eb(wrappedLines.first), width: kColWidths[0]),
        PosColumn(
          textEncoded: eb(sizeStr),
          width: kColWidths[1],
          styles: const PosStyles(align: PosAlign.center),
        ),
        PosColumn(
          text: qtyStr,
          width: kColWidths[2],
          styles: const PosStyles(
            bold: true,
            align: PosAlign.center,
            height: PosTextSize.size2,
          ),
        ),
      ]);

      // Các dòng tên tiếp theo (nếu có)
      for (var i = 1; i < wrappedLines.length; i++) {
        bytes += generator.textEncoded(eb(wrappedLines[i]));
      }

      // Gạch nhẹ phân cách giữa các item
      if (idx < ticket.items.length - 1) {
        bytes += generator.text(kLightHr);
      }
    }

    bytes += generator.hr();

    // ── Note ────────────────────────────────────────────────────
    if (ticket.note.isNotEmpty) {
      bytes += generator.textEncoded(eb('Ghi chú: ${ticket.note}'));
    }

    bytes += generator.feed(1);
    bytes += generator.cut();

    return bytes;
  }

  static List<int> _kitchenColumnWidths(int paperWidth) {
    // 12 columns total: name | size | qty
    if (paperWidth == 80) {
      return [7, 3, 2];
    }
    return [6, 3, 3];
  }

  static List<int> _columnWidths(int paperWidth) {
    if (paperWidth == 80) {
      return [7, 2, 3];
    }
    return [6, 2, 4];
  }

  static int _nameMaxLen(int paperWidth) {
    return paperWidth == 80 ? 20 : 14;
  }

  /// Groups BillItems with same name, sizeName and unitPrice, summing quantities.
  static List<BillItem> _groupBillItems(List<BillItem> items) {
    final map = <String, BillItem>{};
    for (final item in items) {
      final key = '${item.name}|${item.sizeName ?? ''}|${item.unitPrice}';
      if (map.containsKey(key)) {
        final existing = map[key]!;
        map[key] = BillItem(
          name: existing.name,
          sizeName: existing.sizeName,
          quantity: existing.quantity + item.quantity,
          unitPrice: existing.unitPrice,
        );
      } else {
        map[key] = item;
      }
    }
    return map.values.toList();
  }

  /// Tải ảnh từ URL (http/https) hoặc Data URL (data:image/...;base64,...).
  static Future<img.Image?> _downloadImage(String url) async {
    try {
      if (url.startsWith('data:')) {
        // Data URL: data:image/jpeg;base64,<base64data>
        final commaIdx = url.indexOf(',');
        if (commaIdx == -1) return null;
        final base64Data = url.substring(commaIdx + 1);
        final bytes = base64Decode(base64Data);
        return img.decodeImage(bytes);
      } else {
        final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
        if (response.statusCode != 200) return null;
        return img.decodeImage(response.bodyBytes);
      }
    } catch (_) {
      return null;
    }
  }

  /// Word-wraps [text] so each line is at most [maxLen] characters.
  static List<String> _wrapText(String text, int maxLen) {
    if (text.length <= maxLen) return [text];

    final words = text.split(' ');
    final lines = <String>[];
    var current = '';

    for (final word in words) {
      if (current.isEmpty) {
        current = word;
      } else if (current.length + 1 + word.length <= maxLen) {
        current += ' $word';
      } else {
        lines.add(current);
        current = word;
      }
    }
    if (current.isNotEmpty) lines.add(current);

    return lines.isEmpty ? [text] : lines;
  }

  /// In test tất cả byte từ 65 đến 255 theo từng code page ID.
  /// Dùng để xác định máy in đang dùng bảng mã nào cho tiếng Việt.
  ///
  /// [codePageId] — ESC t n: 0=PC437, 2=PC850, 16=WPC1252, 30=PC1257,
  ///                          34=PC1255, 36=PC1258(Vietnamese), v.v.
  ///                Truyền null để in với code page mặc định (không gửi ESC t).
  static Future<List<int>> buildCodePageTest(
    PrinterSettings settings, {
    int? codePageId,
  }) async {
    final profile = await CapabilityProfile.load();
    final paperSize =
        settings.paperWidth == 80 ? PaperSize.mm80 : PaperSize.mm58;
    final generator = Generator(paperSize, profile);

    List<int> bytes = [];

    // ── Tiêu đề ─────────────────────────────────────────────────
    final label = codePageId != null
        ? 'CODE PAGE TEST  ESC t $codePageId'
        : 'CODE PAGE TEST  (default)';
    bytes += generator.text(
      label,
      styles: const PosStyles(bold: true, align: PosAlign.center),
    );
    bytes += generator.text(
      'Bytes 65 - 255',
      styles: const PosStyles(align: PosAlign.center),
    );
    bytes += generator.hr();

    // ── Gửi lệnh ESC t n để chọn code page ──────────────────────
    if (codePageId != null) {
      bytes += [0x1B, 0x74, codePageId]; // ESC t n
    }

    // ── In từng nhóm 8 byte / dòng ──────────────────────────────
    // Format mỗi dòng: "065-072: A B C D E F G H"
    for (var start = 65; start <= 255; start += 8) {
      final end = (start + 7).clamp(65, 255);

      // Prefix: "065-072: "
      final prefix = '${start.toString().padLeft(3, '0')}'
          '-${end.toString().padLeft(3, '0')}: ';

      // Raw bytes cần in (space-separated để dễ nhìn)
      final charBytes = <int>[];
      for (var b = start; b <= end; b++) {
        charBytes.add(b);
        charBytes.add(0x20); // space phân cách
      }

      // Ghép prefix (ASCII an toàn) + raw bytes
      final prefixBytes = Uint8List.fromList(
        prefix.codeUnits.map((c) => c & 0xFF).toList(),
      );
      final lineBytes = Uint8List.fromList([
        ...prefixBytes,
        ...charBytes,
        0x0A, // newline
      ]);

      bytes += lineBytes;
    }

    // ── Reset về code page mặc định ─────────────────────────────
    if (codePageId != null) {
      bytes += [0x1B, 0x74, 0x00]; // ESC t 0 = PC437 (default)
    }

    bytes += generator.hr();
    bytes += generator.text(
      'Het / End',
      styles: const PosStyles(align: PosAlign.center),
    );
    bytes += generator.feed(3);
    bytes += generator.cut();

    return bytes;
  }
}
