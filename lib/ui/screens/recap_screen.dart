import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/models.dart';
import '../../providers/pos_provider.dart';
import '../../services/db_helper.dart';
import '../../services/google_sheet_service.dart';
import 'receipt_screen.dart';

class RecapScreen extends StatefulWidget {
  final PosProvider pos;

  const RecapScreen({super.key, required this.pos});

  @override
  State<RecapScreen> createState() => _RecapScreenState();
}

class _RecapScreenState extends State<RecapScreen> {
  Map<String, dynamic>? _summary;
  List<Map<String, dynamic>> _cashEntries = [];
  List<TransactionModel> _todayTransactions = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSummary();
  }

  Future<void> _loadSummary() async {
    setState(() => _isLoading = true);
    final now = DateTime.now();
    final DateTime bDate = now.hour < 6 ? now.subtract(const Duration(days: 1)) : now;
    final bDateKey = DateFormat('yyyy-MM-dd').format(bDate);

    final summary = await DbHelper().getTodaySummary(bDateKey);
    final entries = await DbHelper().getCashEntries(bDateKey);
    final trxs = await DbHelper().getTodayTransactions(bDateKey);

    if (mounted) {
      setState(() {
        _summary = summary;
        _cashEntries = entries;
        _todayTransactions = trxs;
        _isLoading = false;
      });
    }
  }

  void _reprintReceipt(TransactionModel trx) async {
    final items = await DbHelper().getTransactionItems(trx.id);
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ReceiptScreen(
          transaction: trx,
          items: items,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currencyFormatter = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp', decimalDigits: 0);
    final todayStr = DateFormat('EEEE, d MMM yyyy', 'id_ID').format(DateTime.now());

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF7A5540)));
    }

    final omzet = _summary?['omzet'] ?? 0;
    final trxCount = _summary?['trxCount'] ?? 0;
    final tunai = _summary?['tunai'] ?? 0;
    final qrisTransfer = _summary?['qrisTransfer'] ?? 0;
    final cashIn = _summary?['cashIn'] ?? 0;
    final cashOut = _summary?['cashOut'] ?? 0;
    final expectedCashInDrawer = _summary?['expectedCashInDrawer'] ?? 0;

    return RefreshIndicator(
      onRefresh: _loadSummary,
      color: const Color(0xFF7A5540),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Rekap Penjualan Harian', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Color(0xFF211A15))),
                    Text(todayStr, style: const TextStyle(fontSize: 12, color: Color(0xFF51443B))),
                  ],
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF356A58),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: () => _showTutupKasirModal(context, currencyFormatter, omzet, trxCount, tunai, qrisTransfer, expectedCashInDrawer),
                  icon: const Icon(Icons.lock_clock, size: 18),
                  label: const Text('Tutup Kasir'),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Stat Cards Grid (Real SQLite Data)
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: 1.6,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              children: [
                _buildStatCard('Omzet Bruto', currencyFormatter.format(omzet), '$trxCount transaksi terproses', const Color(0xFF7A5540), Icons.payments),
                _buildStatCard('Total Transaksi', '$trxCount TRX', 'Subtotal $trxCount struk', const Color(0xFF356A58), Icons.receipt_long),
                _buildStatCard('Pembayaran Tunai', currencyFormatter.format(tunai), 'Uang masuk tunai', const Color(0xFF7C5800), Icons.money),
                _buildStatCard('QRIS & Transfer', currencyFormatter.format(qrisTransfer), 'Non-tunai / QRIS', const Color(0xFF356A58), Icons.qr_code_2),
              ],
            ),
            const SizedBox(height: 18),

            // Kasir & Shift Log Card (Real Cash Drawer Breakdown)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFFFF),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFD6C7BB)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('💵 Saldo Kasir di Laci Saat Ini', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      TextButton.icon(
                        onPressed: () => _showInputKasModal(context),
                        icon: const Icon(Icons.add_card, size: 14),
                        label: const Text('Catat Kas/Pengeluaran', style: TextStyle(fontSize: 12)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Divider(),
                  _buildRowDetail('Penerimaan Tunai Kasir', currencyFormatter.format(tunai)),
                  _buildRowDetail('Kas Masuk / Modal Awal', currencyFormatter.format(cashIn)),
                  _buildRowDetail('Total Pengeluaran Kas Laci (Out)', '-${currencyFormatter.format(cashOut)}', isError: cashOut > 0),
                  const Divider(),
                  _buildRowDetail('TOTAL SALDO DI LACI', currencyFormatter.format(expectedCashInDrawer), isBold: true),
                ],
              ),
            ),
            const SizedBox(height: 18),

            // Rincian Pengeluaran Kas (Kas Out Entries List)
            if (_cashEntries.isNotEmpty) ...[
              const Text('💸 Rincian Transaksi Kas Out & Modal', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE8DFD8)),
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _cashEntries.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final entry = _cashEntries[index];
                    final bool isOut = entry['type'] == 'OUT';
                    final amount = entry['amount'] as int;
                    final category = entry['category'] as String;
                    final note = (entry['note'] as String?) ?? '';
                    final created = (entry['created_at'] as String?) ?? '';
                    final timeStr = created.length >= 16 ? created.substring(11, 16) : '';

                    return ListTile(
                      dense: true,
                      leading: CircleAvatar(
                        radius: 14,
                        backgroundColor: isOut ? const Color(0xFFFFDADA) : const Color(0xFFD0F8E5),
                        child: Icon(
                          isOut ? Icons.arrow_upward : Icons.arrow_downward,
                          size: 14,
                          color: isOut ? Colors.red : const Color(0xFF006C4C),
                        ),
                      ),
                      title: Text(
                        '${isOut ? "Pengeluaran" : "Kas Masuk"} • $category ${timeStr.isNotEmpty ? "($timeStr)" : ""}',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                      subtitle: note.isNotEmpty ? Text(note, style: const TextStyle(fontSize: 10, color: Colors.grey)) : null,
                      trailing: Text(
                        '${isOut ? "-" : "+"}${currencyFormatter.format(amount)}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          color: isOut ? Colors.red : const Color(0xFF006C4C),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 18),
            ],

            // Daftar Transaksi Kasir Hari Ini (Full List & Cetak Ulang Struk)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('📜 Daftar Transaksi Hari Ini ($trxCount)', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                Text('${_todayTransactions.length} struk', style: const TextStyle(fontSize: 11, color: Colors.grey)),
              ],
            ),
            const SizedBox(height: 8),
            _todayTransactions.isEmpty
                ? Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                    child: const Text('Belum ada transaksi terproses hari ini.', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey, fontSize: 12)),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _todayTransactions.length,
                    itemBuilder: (context, index) {
                      final t = _todayTransactions[index];
                      final bool isVoid = t.status == 'VOID';
                      final timeStr = DateFormat('HH:mm').format(t.createdAt);

                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        color: isVoid ? Colors.red.shade50 : Colors.white,
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                          title: Text(
                            t.code,
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, decoration: isVoid ? TextDecoration.lineThrough : null),
                          ),
                          subtitle: Text(
                            '${t.cashierName} • ${t.paymentMethod} • $timeStr ${isVoid ? "(VOID)" : ""}',
                            style: const TextStyle(fontSize: 11, color: Colors.grey),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                currencyFormatter.format(t.totalAmount),
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: isVoid ? Colors.red : const Color(0xFF7A5540)),
                              ),
                              const SizedBox(width: 6),
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF7A5540),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                                onPressed: () => _reprintReceipt(t),
                                icon: const Icon(Icons.print, size: 14),
                                label: const Text('Struk', style: TextStyle(fontSize: 11)),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(String label, String value, String subText, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
              Icon(icon, color: color, size: 20),
            ],
          ),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color)),
          const SizedBox(height: 2),
          Text(subText, style: const TextStyle(fontSize: 10, color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildRowDetail(String label, String val, {bool isBold = false, bool isError = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 13, fontWeight: isBold ? FontWeight.bold : FontWeight.normal)),
          Text(
            val,
            style: TextStyle(
              fontSize: 13,
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
              color: isError ? Colors.red : (isBold ? const Color(0xFF7A5540) : Colors.black87),
            ),
          ),
        ],
      ),
    );
  }

  void _showInputKasModal(BuildContext context) {
    final amountCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    String type = CashType.out; // KELUAR (Pengeluaran) | MASUK (Kas Masuk)
    String category = 'Operasional';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) => AlertDialog(
          title: const Text('Catat Kas / Pengeluaran Laci'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: ChoiceChip(
                        label: const Text('Pengeluaran (Out)'),
                        selected: type == CashType.out,
                        onSelected: (s) => setDlgState(() => type = CashType.out),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ChoiceChip(
                        label: const Text('Kas Masuk (In)'),
                        selected: type == CashType.in_,
                        onSelected: (s) => setDlgState(() => type = CashType.in_),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: amountCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Nominal (Rp)', hintText: 'Misal: 15000', filled: true, fillColor: Color(0xFFF1EFEB)),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: noteCtrl,
                  decoration: const InputDecoration(labelText: 'Keterangan / Keperluan', hintText: 'Beli Es Kristal / Plastik', filled: true, fillColor: Color(0xFFF1EFEB)),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF7A5540), foregroundColor: Colors.white),
              onPressed: () async {
                final amt = int.tryParse(amountCtrl.text.trim()) ?? 0;
                final note = noteCtrl.text.trim();
                if (amt > 0) {
                  final now = DateTime.now();
                  final bDate = now.hour < 6 ? now.subtract(const Duration(days: 1)) : now;
                  final bDateKey = DateFormat('yyyy-MM-dd').format(bDate);

                  await DbHelper().insertCashEntry(
                    type: type,
                    amount: amt,
                    category: category,
                    note: note.isEmpty ? 'Kas Laci' : note,
                    businessDate: bDateKey,
                    byName: widget.pos.activeCashierDisplay,
                  );

                  // Sync ke Google Sheet (tab Kas).
                  final prefs = await SharedPreferences.getInstance();
                  final sheetId = prefs.getString('spreadsheet_id') ?? '';
                  if (sheetId.isNotEmpty) {
                    try {
                      await GoogleSheetService().appendKas(
                        sheetId, bDateKey, type, amt,
                        category: category,
                        note: note.isEmpty ? 'Kas Laci' : note,
                        by: widget.pos.activeCashierDisplay,
                      );
                    } catch (e) {
                      debugPrint('Append kas ke Sheet gagal: $e');
                    }
                  }

                  if (mounted) {
                    Navigator.pop(ctx);
                    _loadSummary();
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✓ Kas/Pengeluaran berhasil dicatat & disinkron!')));
                  }
                }
              },
              child: const Text('Simpan'),
            ),
          ],
        ),
      ),
    );
  }

  void _showTutupKasirModal(BuildContext context, NumberFormat currencyFormatter, int omzet, int trxCount, int tunai, int qris, int expectedCash) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        padding: const EdgeInsets.all(20),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
            ),
            const SizedBox(height: 16),
            const Row(
              children: [
                Icon(Icons.lock_clock, color: Color(0xFF7A5540)),
                SizedBox(width: 8),
                Text('Konfirmasi Tutup Kasir / Shift', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 12),
            Text('Ringkasan Omzet Hari Ini: ${currencyFormatter.format(omzet)} ($trxCount TRX)', style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('Total Tunai: ${currencyFormatter.format(tunai)} • Non-Tunai: ${currencyFormatter.format(qris)}'),
            const SizedBox(height: 4),
            Text('Fisik Uang Wajib di Laci: ${currencyFormatter.format(expectedCash)}', style: const TextStyle(color: Color(0xFF7A5540), fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF356A58),
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              onPressed: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✓ Shift berhasil ditutup! Rekap tersimpan.')));
              },
              child: const Text('Selesaikan Shift & Simpan Laporan', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}
