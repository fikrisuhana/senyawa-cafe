import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/models.dart';

class ReceiptScreen extends StatelessWidget {
  final TransactionModel transaction;
  final List<CartItem> items;

  const ReceiptScreen({
    super.key,
    required this.transaction,
    required this.items,
  });

  Future<Map<String, String>> _loadReceiptSettings() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'header': prefs.getString('receipt_header') ?? 'Ruang Senyawa Coffee\nInstagram: @r_senyawa',
      'footer': prefs.getString('receipt_footer') ?? 'WiFi      : Ruang Senyawa\nPassword  : followIGdulu\n\nTerima kasih sudah menjadi bagian \ndari cerita di Ruang Senyawa.',
      'printerName': prefs.getString('printer_name') ?? 'POS-5802',
      'paperSize': prefs.getString('paper_size') ?? '58mm',
      'showLogo': (prefs.getBool('receipt_show_logo') ?? true).toString(),
    };
  }

  Uint8List _buildEscPosBytes(
    String printerName,
    String paperSize,
    String headerText,
    String footerText,
    NumberFormat currencyFormatter,
    DateFormat dateFormatter, {
    bool kitchen = false,
  }) {
    final List<int> bytes = [];

    // Reset printer
    bytes.addAll([0x1B, 0x40]);

    // Center alignment
    bytes.addAll([0x1B, 0x61, 0x01]);

    // Header Title
    bytes.addAll([0x1B, 0x45, 0x01]); // Bold
    bytes.addAll(kitchen ? '*** STRUK DAPUR ***\n'.codeUnits : '$headerText\n'.codeUnits);
    bytes.addAll([0x1B, 0x45, 0x00]);

    bytes.addAll('--------------------------------\n'.codeUnits);

    // Left alignment
    bytes.addAll([0x1B, 0x61, 0x00]);

    // Trx info
    bytes.addAll('No   : ${transaction.code}\n'.codeUnits);
    bytes.addAll('Waktu: ${dateFormatter.format(transaction.createdAt)}\n'.codeUnits);
    bytes.addAll('Kasir: ${transaction.cashierName}\n'.codeUnits);
    bytes.addAll('Tipe : ${transaction.orderType == 'DINE_IN' ? 'Di Tempat' : 'Bungkus'}\n'.codeUnits);

    bytes.addAll('--------------------------------\n'.codeUnits);

    // Items
    for (final item in items) {
      final nameStr = '${item.quantity}x ${item.menu.name}';
      final priceStr = currencyFormatter.format(item.totalPrice);

      bytes.addAll('$nameStr\n'.codeUnits);
      if (item.selectedVariants.isNotEmpty) {
        bytes.addAll('  • ${item.variantDescription}\n'.codeUnits);
      }
      if (item.note.isNotEmpty) {
        bytes.addAll('  (Catatan: ${item.note})\n'.codeUnits);
      }
      bytes.addAll('  ${item.quantity} x ${currencyFormatter.format(item.unitPrice)} = $priceStr\n'.codeUnits);
    }

    bytes.addAll('--------------------------------\n'.codeUnits);

    // Totals (hanya struk pelanggan; struk dapur tanpa harga)
    if (!kitchen) {
      // Subtotal & diskon hanya kalau ada potongan (biar tak dobel dgn Total).
      if (transaction.discountAmount > 0) {
        bytes.addAll('Subtotal: ${currencyFormatter.format(transaction.subtotal)}\n'.codeUnits);
        bytes.addAll('Diskon  : -${currencyFormatter.format(transaction.discountAmount)}\n'.codeUnits);
      }
      bytes.addAll([0x1B, 0x45, 0x01]); // Bold
      bytes.addAll('TOTAL   : ${currencyFormatter.format(transaction.totalAmount)}\n'.codeUnits);
      bytes.addAll([0x1B, 0x45, 0x00]);
      bytes.addAll('Bayar   : ${currencyFormatter.format(transaction.cashReceived)}\n'.codeUnits);
      bytes.addAll('Kembali : ${currencyFormatter.format(transaction.changeAmount)}\n'.codeUnits);
      bytes.addAll('--------------------------------\n'.codeUnits);
    }

    // Center alignment
    bytes.addAll([0x1B, 0x61, 0x01]);
    bytes.addAll(kitchen ? '-- untuk dapur --\n\n\n\n'.codeUnits : '$footerText\n\n\n\n'.codeUnits);

    // Feed lines
    bytes.addAll([0x1B, 0x64, 0x04]);

    return Uint8List.fromList(bytes);
  }

  @override
  Widget build(BuildContext context) {
    final currencyFormatter = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp', decimalDigits: 0);
    final dateFormatter = DateFormat('dd MMM yyyy HH:mm');

    return Scaffold(
      backgroundColor: const Color(0xFFF4ECE6),
      appBar: AppBar(
        title: const Text('🖨️ Cetak Struk Kasir (ESC/POS)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        backgroundColor: const Color(0xFF7A5540),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: FutureBuilder<Map<String, String>>(
        future: _loadReceiptSettings(),
        builder: (context, snapshot) {
          final headerText = snapshot.data?['header'] ?? 'Ruang Senyawa Coffee\nInstagram: @r_senyawa';
          final footerText = snapshot.data?['footer'] ?? 'WiFi      : Ruang Senyawa\nPassword  : followIGdulu\n\nTerima kasih sudah menjadi bagian \ndari cerita di Ruang Senyawa.';
          final printerName = snapshot.data?['printerName'] ?? 'POS-5802';
          final paperSize = snapshot.data?['paperSize'] ?? '58mm';
          final showLogo = (snapshot.data?['showLogo'] ?? 'true') != 'false';

          return SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            child: Column(
              children: [
                // Active Printer Connection Banner
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFB7F1DC),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFF356A58), width: 1.5),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.bluetooth_connected, color: Color(0xFF356A58), size: 24),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '🟢 PRINTER TARGET: $printerName ($paperSize)',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF00201A)),
                            ),
                            const Text(
                              'Siap Kirim Sinyal Langsung ke Bluetooth RFCOMM Socket',
                              style: TextStyle(fontSize: 11, color: Color(0xFF356A58)),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Authentic 58mm Thermal Paper Roll Card
                Center(
                  child: Container(
                    width: 320,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 16,
                          spreadRadius: 4,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Shop Header (logo diset dari Setelan Struk)
                        if (showLogo) ...[
                          Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              color: const Color(0xFF1A73E8),
                              shape: BoxShape.circle,
                              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 4)],
                            ),
                            child: ClipOval(
                              child: Image.asset(
                                'assets/seed/logo.jpg',
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => const Center(
                                  child: Text('RS', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 20)),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                        ],
                        Text(
                          headerText,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, height: 1.3),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          '- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -',
                          style: TextStyle(color: Colors.grey.shade400, fontSize: 10, letterSpacing: 1),
                        ),
                        const SizedBox(height: 8),

                        // Trx Meta
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('No: ${transaction.code}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                            Text(dateFormatter.format(transaction.createdAt), style: const TextStyle(fontSize: 10, color: Colors.grey)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Kasir: ${transaction.cashierName}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                            Text(transaction.orderType == 'DINE_IN' ? '🍽️ Di tempat' : '🥡 Bungkus', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF7A5540))),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -',
                          style: TextStyle(color: Colors.grey.shade400, fontSize: 10, letterSpacing: 1),
                        ),
                        const SizedBox(height: 8),

                        // Item List
                        ...items.map((item) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        '${item.quantity}x ${item.menu.name}',
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                                      ),
                                    ),
                                    Text(
                                      currencyFormatter.format(item.totalPrice),
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                                    ),
                                  ],
                                ),
                                if (item.selectedVariants.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(left: 12, top: 2),
                                    child: Text(
                                      '• ${item.variantDescription}',
                                      style: TextStyle(fontSize: 10, color: Colors.grey.shade700, fontStyle: FontStyle.italic),
                                    ),
                                  ),
                                if (item.note.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(left: 12, top: 1),
                                    child: Text(
                                      '  (Catatan: ${item.note})',
                                      style: const TextStyle(fontSize: 10, color: Color(0xFF7C5800)),
                                    ),
                                  ),
                              ],
                            ),
                          );
                        }),

                        const SizedBox(height: 8),
                        Text(
                          '- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -',
                          style: TextStyle(color: Colors.grey.shade400, fontSize: 10, letterSpacing: 1),
                        ),
                        const SizedBox(height: 8),

                        // Subtotal + diskon HANYA kalau ada potongan (biar tak dobel dgn Total)
                        if (transaction.discountAmount > 0) ...[
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Subtotal', style: TextStyle(fontSize: 11, color: Colors.grey)),
                              Text(currencyFormatter.format(transaction.subtotal), style: const TextStyle(fontSize: 11)),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Diskon / Voucher', style: TextStyle(fontSize: 11, color: Color(0xFF7C5800), fontWeight: FontWeight.bold)),
                              Text('-${currencyFormatter.format(transaction.discountAmount)}', style: const TextStyle(fontSize: 11, color: Color(0xFF7C5800), fontWeight: FontWeight.bold)),
                            ],
                          ),
                          const SizedBox(height: 6),
                        ],
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('TOTAL BAYAR', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                            Text(
                              currencyFormatter.format(transaction.totalAmount),
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF7A5540)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Tunai / Kembali', style: TextStyle(fontSize: 11, color: Colors.grey)),
                            Text(
                              '${currencyFormatter.format(transaction.cashReceived)} / ${currencyFormatter.format(transaction.changeAmount)}',
                              style: const TextStyle(fontSize: 11, color: Colors.grey),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          '- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -',
                          style: TextStyle(color: Colors.grey.shade400, fontSize: 10, letterSpacing: 1),
                        ),
                        const SizedBox(height: 10),

                        // Footer Text
                        Text(
                          footerText,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 10, color: Colors.grey, height: 1.3),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Cetak 2×: Pelanggan & Dapur (tidak keluar otomatis)
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF356A58),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          elevation: 2,
                        ),
                        onPressed: () => _triggerDirectPrint(context, printerName, paperSize, headerText, footerText, currencyFormatter, dateFormatter),
                        icon: const Icon(Icons.receipt, size: 18),
                        label: const Text('Struk Pelanggan', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF7A5540),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          elevation: 2,
                        ),
                        onPressed: () => _triggerDirectPrint(context, printerName, paperSize, headerText, footerText, currencyFormatter, dateFormatter, kitchen: true),
                        icon: const Icon(Icons.soup_kitchen, size: 18),
                        label: const Text('Struk Dapur', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF356A58),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      side: const BorderSide(color: Color(0xFF356A58), width: 1.5),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.check_circle, size: 20),
                    label: const Text('Selesai — kembali ke Kasir', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  ),
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: () => _showEscPosDialog(context, headerText, footerText, currencyFormatter, dateFormatter),
                  icon: const Icon(Icons.receipt_long, size: 16),
                  label: const Text('Lihat format ESC/POS', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _triggerDirectPrint(
    BuildContext context,
    String printerName,
    String paperSize,
    String headerText,
    String footerText,
    NumberFormat currencyFormatter,
    DateFormat dateFormatter, {
    bool kitchen = false,
  }) async {
    final label = kitchen ? 'Struk Dapur' : 'Struk Pelanggan';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('⚡ Mengirim $label ke "$printerName"...'),
        backgroundColor: const Color(0xFF7A5540),
        duration: const Duration(seconds: 2),
      ),
    );

    final bytes = _buildEscPosBytes(printerName, paperSize, headerText, footerText, currencyFormatter, dateFormatter, kitchen: kitchen);

    try {
      const platform = MethodChannel('id.ruangsenyawa.pos/printer');
      await platform.invokeMethod('printBytes', {
        'printerName': printerName,
        'bytes': bytes,
      });

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ $label terkirim ke "$printerName" 🎉'),
            backgroundColor: const Color(0xFF356A58),
            duration: const Duration(seconds: 2),
          ),
        );
        // Sengaja TIDAK keluar — biar bisa cetak lagi (pelanggan / dapur).
      }
    } catch (e) {
      if (context.mounted) {
        final errStr = e.toString().replaceAll('PlatformException(', '').replaceAll(')', '');
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Text('⚠️ Status Cetak Bluetooth'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  errStr,
                  style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Solusi Cepat:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                ),
                const SizedBox(height: 4),
                const Text(
                  '1. Pastikan Bluetooth HP dinyalakan.\n'
                  '2. Sandingkan (Pair) printer di Pengaturan Bluetooth HP (PIN: 0000 atau 1234).\n'
                  '3. Pastikan nama printer yang dipilih di Admin Hub sama persis dengan di Bluetooth HP.',
                  style: TextStyle(fontSize: 11, height: 1.3),
                ),
              ],
            ),
            actions: [
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF7A5540), foregroundColor: Colors.white),
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Mengerti'),
              ),
            ],
          ),
        );
      }
    }
  }

  void _showEscPosDialog(BuildContext context, String headerText, String footerText, NumberFormat currencyFormatter, DateFormat dateFormatter) {
    final buf = StringBuffer();
    buf.writeln('=== RUANG SENYAWA ===');
    buf.writeln('Kode  : ${transaction.code}');
    buf.writeln('Waktu : ${dateFormatter.format(transaction.createdAt)}');
    buf.writeln('Kasir : ${transaction.cashierName}');
    buf.writeln('Tipe  : ${transaction.orderType}');
    buf.writeln('--------------------------------');
    for (final it in items) {
      buf.writeln('${it.quantity}x ${it.menu.name}');
      if (it.variantDescription.isNotEmpty) {
        buf.writeln('   (${it.variantDescription})');
      }
      buf.writeln('   ${currencyFormatter.format(it.totalPrice)}');
    }
    buf.writeln('--------------------------------');
    buf.writeln('Total : ${currencyFormatter.format(transaction.totalAmount)}');
    buf.writeln('Bayar : ${currencyFormatter.format(transaction.cashReceived)}');
    buf.writeln('Kembali: ${currencyFormatter.format(transaction.changeAmount)}');
    buf.writeln('================================');

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('📄 Format Text ESC/POS Thermal'),
        content: SingleChildScrollView(
          child: SelectableText(buf.toString(), style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Tutup')),
        ],
      ),
    );
  }
}
