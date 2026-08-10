import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/models.dart';
import '../../providers/pos_provider.dart';
import '../../providers/settings_provider.dart';
import '../../services/db_helper.dart';
import '../../services/google_sheet_service.dart';
import 'package:intl/intl.dart';
import 'splash_setup_screen.dart';
import 'receipt_screen.dart';

class AdminHubScreen extends StatefulWidget {
  final SettingsProvider settings;
  final PosProvider pos;
  final VoidCallback? onLockAdmin;

  const AdminHubScreen({
    super.key,
    required this.settings,
    required this.pos,
    this.onLockAdmin,
  });

  @override
  State<AdminHubScreen> createState() => _AdminHubScreenState();
}

class _AdminHubScreenState extends State<AdminHubScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _sheetId = '1RuangSenyawaLedger2026';
  String _printerName = 'Belum Diatur';
  String _paperSize = '58mm';
  bool _autoPrint = true;
  List<Map<String, dynamic>> _employees = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _loadInitialData();
    widget.pos.addListener(_onPosChanged); // refresh list saat katalog berubah
  }

  void _onPosChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.pos.removeListener(_onPosChanged);
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    final prefs = await SharedPreferences.getInstance();
    final emps = await DbHelper().getEmployees();
    setState(() {
      _sheetId = prefs.getString('spreadsheet_id') ?? '1RuangSenyawaLedger2026';
      _printerName = prefs.getString('printer_name') ?? 'RPP02N / Thermal 58mm';
      _paperSize = prefs.getString('paper_size') ?? '58mm';
      _autoPrint = prefs.getBool('auto_print') ?? true;
      _employees = emps;
    });
  }

  void _handleExitAdmin() {
    widget.settings.lockAdmin();
    if (widget.onLockAdmin != null) {
      widget.onLockAdmin!();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          color: const Color(0xFFF5F3F0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('🔓 Mode Admin Unlocked', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1A73E8))),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade700,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: _handleExitAdmin,
                icon: const Icon(Icons.lock, size: 14),
                label: const Text('Keluar Admin', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
        TabBar(
          controller: _tabController,
          isScrollable: true,
          labelColor: const Color(0xFF1A73E8),
          unselectedLabelColor: Colors.grey,
          indicatorColor: const Color(0xFF1A73E8),
          tabs: const [
            Tab(text: 'Setelan App'),
            Tab(text: 'Kelola Menu'),
            Tab(text: 'Stok & Bahan'),
            Tab(text: 'Voucher'),
            Tab(text: 'Staf / Karyawan'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildSettingsTab(),
              _buildMenuAdminTab(),
              _buildStokAdminTab(),
              _buildVoucherAdminTab(),
              _buildStafAdminTab(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSettingsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Text Scaling Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('🗚 Ukuran Teks Aplikasi (In-App Scaling)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  const SizedBox(height: 4),
                  const Text('Atur skala font untuk kenyamanan HP atau Tablet:', style: TextStyle(fontSize: 11, color: Colors.grey)),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: ChoiceChip(
                          label: const Center(child: Text('🗛 Ringkas (88%)')),
                          selected: widget.settings.fontScale == 0.88,
                          selectedColor: const Color(0xFFB7F1DC),
                          onSelected: (_) => widget.settings.setFontScale(0.88),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: ChoiceChip(
                          label: const Center(child: Text('A Normal (100%)')),
                          selected: widget.settings.fontScale == 1.0,
                          selectedColor: const Color(0xFFB7F1DC),
                          onSelected: (_) => widget.settings.setFontScale(1.0),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: ChoiceChip(
                          label: const Center(child: Text('🗚 Besar (115%)')),
                          selected: widget.settings.fontScale == 1.15,
                          selectedColor: const Color(0xFFB7F1DC),
                          onSelected: (_) => widget.settings.setFontScale(1.15),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Printer Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('🖨️ Printer Thermal Bluetooth', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF1A73E8)),
                        onPressed: _showPrinterSettingsDialog,
                        icon: const Icon(Icons.settings, size: 16),
                        label: const Text('Atur'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text('Printer Terhubung: $_printerName ($_paperSize)', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  Text('Cetak Struk Otomatis: ${_autoPrint ? 'Aktif' : 'Non-aktif'}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0F9D58), foregroundColor: Colors.white),
                      onPressed: _showTestPrintDialog,
                      icon: const Icon(Icons.print, size: 16),
                      label: const Text('Tes Cetak Struk ke Printer'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Setelan Struk Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Expanded(child: Text('🧾 Setelan Struk', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14))),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF7A5540)),
                        onPressed: _showReceiptSettingsDialog,
                        icon: const Icon(Icons.edit_note, size: 16),
                        label: const Text('Atur'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text('Atur tulisan atas/bawah struk, ukuran kertas 58/80mm, & tampil-tidaknya logo.', style: TextStyle(fontSize: 12, color: Colors.grey)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Security PIN Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('🔑 Keamanan & PIN Admin', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF7A5540)),
                        onPressed: _showChangePinDialog,
                        icon: const Icon(Icons.lock_reset, size: 16),
                        label: const Text('Ganti PIN'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text('PIN Master disimpan lokal di perangkat ini (belum tersinkron ke Sheet).', style: TextStyle(fontSize: 11, color: Colors.grey)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Theme Selector Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('📱 Tampilan & Tema', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Tema Terang / Gelap'),
                      Switch(
                        value: widget.settings.isDarkMode,
                        activeThumbColor: const Color(0xFF7A5540),
                        onChanged: (val) => widget.settings.toggleDarkMode(val),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Google Sheet Config Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('🔄 Integrasi Google Sheet', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  const SizedBox(height: 4),
                  Text('Spreadsheet ID Active: $_sheetId', style: const TextStyle(fontSize: 11, color: Colors.grey), overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF356A58), foregroundColor: Colors.white),
                        onPressed: () {
                          widget.pos.performSync();
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✓ Sync Google Sheet diproses di background!')));
                        },
                        icon: const Icon(Icons.sync, size: 16),
                        label: const Text('Sinkron Sekarang'),
                      ),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF7A5540)),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const SplashSetupScreen(isReconfiguring: true)),
                          );
                        },
                        icon: const Icon(Icons.key, size: 16),
                        label: const Text('Ganti Akun / Sheet ID'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuAdminTab() {
    final items = widget.pos.menuItems;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF7A5540),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () => _showMenuDialog(),
              icon: const Icon(Icons.add),
              label: const Text('+ Tambah Menu Baru', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: ListTile(
                  title: Text(item.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Kategori: ${item.category} • Rp${item.price}', style: const TextStyle(fontSize: 12)),
                      const SizedBox(height: 4),
                      FutureBuilder<List<Map<String, dynamic>>>(
                        future: DbHelper().getMenuStocks(item.name),
                        builder: (ctx, snap) {
                          final stocks = snap.data ?? [];
                          if (stocks.isEmpty) {
                            return const Text('🧪 Resep Bahan: Belum diatur (atur di tombol ✏️ Edit)', style: TextStyle(fontSize: 11, color: Colors.orange, fontStyle: FontStyle.italic));
                          }
                          final desc = stocks.map((s) => '${s['packaging_name']} (${s['qty']}x)').join(', ');
                          return Text('🧪 Resep Bahan: $desc', style: const TextStyle(fontSize: 11, color: Color(0xFF356A58), fontWeight: FontWeight.bold));
                        },
                      ),
                    ],
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                        icon: const Icon(Icons.tune, color: Color(0xFF1A73E8), size: 20),
                        tooltip: 'Atur Varian (Dingin/Panas/Topping)',
                        onPressed: () => _showManageVariantsDialog(item),
                      ),
                      IconButton(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                        icon: const Icon(Icons.edit, color: Color(0xFF1A73E8), size: 20),
                        onPressed: () => _showMenuDialog(itemToEdit: item),
                      ),
                      IconButton(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                        icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                        onPressed: () => _confirmDeleteMenu(item),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildStokAdminTab() {
    final packagings = widget.pos.packagings;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF7A5540),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: _showAddPackagingDialog,
              icon: const Icon(Icons.inventory),
              label: const Text('+ Tambah Bahan / Kemasan Baru', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: packagings.length,
            itemBuilder: (context, index) {
              final pkg = packagings[index];
              final bool isLow = pkg.stock <= pkg.minStock;

              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  onTap: () => _showRestokDialog(pkg),
                  leading: CircleAvatar(
                    backgroundColor: isLow ? const Color(0xFFFFDEA1) : const Color(0xFFB7F1DC),
                    child: Icon(
                      isLow ? Icons.warning_amber : Icons.inventory_2,
                      color: isLow ? const Color(0xFF7C5800) : const Color(0xFF356A58),
                    ),
                  ),
                  title: Text(pkg.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  subtitle: Text(
                    'Stok Saat Ini: ${pkg.stock} ${pkg.unit} (Min: ${pkg.minStock})',
                    style: TextStyle(fontSize: 12, color: isLow ? Colors.red : Colors.grey.shade700),
                  ),
                  trailing: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF7A5540),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () => _showRestokDialog(pkg),
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Restok'),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  void _showAddPackagingDialog() {
    final nameCtrl = TextEditingController();
    final unitCtrl = TextEditingController(text: 'pcs');
    final stockCtrl = TextEditingController(text: '100');
    final minCtrl = TextEditingController(text: '20');

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('📦 Tambah Bahan / Kemasan Baru'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: 'Nama Bahan / Kemasan', hintText: 'Misal: Sedotan Boba', filled: true, fillColor: Color(0xFFF1EFEB)),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: unitCtrl,
              decoration: const InputDecoration(labelText: 'Satuan', hintText: 'pcs / ml / gram', filled: true, fillColor: Color(0xFFF1EFEB)),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: stockCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Stok Awal', hintText: '100', filled: true, fillColor: Color(0xFFF1EFEB)),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: minCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Stok Minimal Warning', hintText: '20', filled: true, fillColor: Color(0xFFF1EFEB)),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF7A5540), foregroundColor: Colors.white),
            onPressed: () async {
              final name = nameCtrl.text.trim();
              final unit = unitCtrl.text.trim();
              final stock = int.tryParse(stockCtrl.text.trim()) ?? 0;
              final min = int.tryParse(minCtrl.text.trim()) ?? 0;

              if (name.isNotEmpty) {
                await DbHelper().insertPackaging(name, unit.isEmpty ? 'pcs' : unit, stock, min);
                await widget.pos.syncCatalogUp();
                if (mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('✓ Bahan $name berhasil ditambahkan!')));
                }
              }
            },
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
  }

  Widget _buildVoucherAdminTab() {
    final vouchers = widget.pos.vouchers;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF7A5540),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () => _showVoucherDialog(),
              icon: const Icon(Icons.confirmation_number_outlined),
              label: const Text('+ Tambah Voucher Baru', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: vouchers.length,
            itemBuilder: (context, index) {
              final v = vouchers[index];
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: ListTile(
                  title: Text(v.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  subtitle: Text(
                    'Tipe: ${v.type} • Nilai: ${v.type == 'PERCENT' ? '${v.value}%' : 'Rp${v.value}'} • Terpakai: ${v.usedCount}/${v.kuota ?? '∞'}',
                    style: const TextStyle(fontSize: 11),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Switch(
                        value: v.active,
                        activeThumbColor: const Color(0xFF7A5540),
                        onChanged: (val) async {
                          final updated = VoucherModel(
                            id: v.id,
                            name: v.name,
                            type: v.type,
                            value: v.value,
                            active: val,
                            kuota: v.kuota,
                            usedCount: v.usedCount,
                            validFrom: v.validFrom,
                            validUntil: v.validUntil,
                          );
                          await DbHelper().updateVoucher(updated);
                          await widget.pos.syncCatalogUp();
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.edit, color: Color(0xFF7A5540)),
                        onPressed: () => _showVoucherDialog(itemToEdit: v),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.red),
                        onPressed: () => _confirmDeleteVoucher(v),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildStafAdminTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF7A5540),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: _showAddEmployeeDialog,
              icon: const Icon(Icons.person_add),
              label: const Text('+ Tambah Karyawan / Kasir Baru', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: _employees.length,
            itemBuilder: (context, index) {
              final emp = _employees[index];
              final name = emp['name'] as String;
              final shiftStatus = (emp['shift_status'] as String?) ?? '';

              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Color(0xFFF5F3F0),
                    child: Icon(Icons.person, color: Color(0xFF7A5540)),
                  ),
                  title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  subtitle: Text('Status Shift: ${shiftStatus.isEmpty ? "Belum Absen" : shiftStatus}', style: const TextStyle(fontSize: 12)),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // --- DIALOG MODALS ---

  void _showMenuDialog({MenuItemModel? itemToEdit}) async {
    final packs = widget.pos.packagings;
    // Muat bahan/resep yang sudah ada (kalau edit) — biar bisa diedit INLINE seperti web.
    final List<Map<String, dynamic>> bahanRows = [];
    if (itemToEdit != null) {
      final stocks = await DbHelper().getMenuStocks(itemToEdit.name);
      for (final s in stocks) {
        bahanRows.add({'packaging': s['packaging_name'] as String, 'qty': (s['qty'] ?? 1) as int});
      }
    }
    if (!mounted) return;

    final nameCtrl = TextEditingController(text: itemToEdit?.name ?? '');
    final priceCtrl = TextEditingController(text: itemToEdit != null ? itemToEdit.price.toString() : '');
    final costCtrl = TextEditingController(text: itemToEdit != null ? itemToEdit.cost.toString() : '0');
    String selectedCat = itemToEdit?.category ?? 'KOPI';

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setDlgState) {
          return AlertDialog(
            title: Text(itemToEdit == null ? '🍽️ Tambah Menu Baru' : '✏️ Edit Menu: ${itemToEdit.name}'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(labelText: 'Nama Menu', hintText: 'Misal: Matcha Latte', filled: true, fillColor: Color(0xFFF1EFEB)),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    value: selectedCat,
                    decoration: const InputDecoration(labelText: 'Kategori', filled: true, fillColor: Color(0xFFF1EFEB)),
                    items: const ['KOPI', 'NON-KOPI', 'MAKANAN', 'SNACK'].map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                    onChanged: (val) => setDlgState(() => selectedCat = val!),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(child: TextField(controller: priceCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Harga Jual (Rp)', filled: true, fillColor: Color(0xFFF1EFEB)))),
                      const SizedBox(width: 8),
                      Expanded(child: TextField(controller: costCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Modal (Rp)', filled: true, fillColor: Color(0xFFF1EFEB)))),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Bahan / Stok dipakai', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      TextButton.icon(
                        onPressed: packs.isEmpty ? null : () => setDlgState(() => bahanRows.add({'packaging': packs.first.name, 'qty': 1})),
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('Tambah bahan', style: TextStyle(fontSize: 12)),
                      ),
                    ],
                  ),
                  if (packs.isEmpty)
                    const Text('Belum ada bahan. Tambah dulu di tab "Stok & Bahan".', style: TextStyle(fontSize: 11, color: Colors.orange, fontStyle: FontStyle.italic))
                  else if (bahanRows.isEmpty)
                    const Text('Menu ini tak memotong bahan. Klik "Tambah bahan" kalau perlu.', style: TextStyle(fontSize: 11, color: Colors.grey))
                  else
                    ...bahanRows.asMap().entries.map((entry) {
                      final i = entry.key;
                      final row = entry.value;
                      final pkgName = packs.any((p) => p.name == row['packaging']) ? row['packaging'] as String : packs.first.name;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                value: pkgName,
                                isDense: true,
                                decoration: const InputDecoration(filled: true, fillColor: Color(0xFFF1EFEB), contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6)),
                                items: packs.map((p) => DropdownMenuItem(value: p.name, child: Text(p.name, style: const TextStyle(fontSize: 12)))).toList(),
                                onChanged: (v) => setDlgState(() => row['packaging'] = v),
                              ),
                            ),
                            IconButton(icon: const Icon(Icons.remove, size: 18), onPressed: () => setDlgState(() { final q = row['qty'] as int; if (q > 1) row['qty'] = q - 1; })),
                            Text('${row['qty']}', style: const TextStyle(fontWeight: FontWeight.bold)),
                            IconButton(icon: const Icon(Icons.add, size: 18), onPressed: () => setDlgState(() => row['qty'] = (row['qty'] as int) + 1)),
                            IconButton(icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red), onPressed: () => setDlgState(() => bahanRows.removeAt(i))),
                          ],
                        ),
                      );
                    }),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF7A5540), foregroundColor: Colors.white),
                onPressed: () async {
                  final name = nameCtrl.text.trim();
                  final price = int.tryParse(priceCtrl.text.trim()) ?? 0;
                  final cost = int.tryParse(costCtrl.text.trim()) ?? 0;
                  if (name.isEmpty || price <= 0) return;

                  if (itemToEdit == null) {
                    await DbHelper().insertMenuItem(MenuItemModel(id: DateTime.now().millisecondsSinceEpoch, name: name, category: selectedCat, price: price, cost: cost, active: true, sortOrder: 0));
                  } else {
                    await DbHelper().updateMenuItem(MenuItemModel(id: itemToEdit.id, name: name, category: selectedCat, price: price, cost: cost, active: itemToEdit.active, sortOrder: itemToEdit.sortOrder));
                  }

                  // Simpan bahan/resep KHUSUS menu ini (hapus lama → insert baru).
                  if (itemToEdit != null && itemToEdit.name != name) {
                    await DbHelper().deleteMenuStocksByMenu(itemToEdit.name);
                  }
                  await DbHelper().deleteMenuStocksByMenu(name);
                  for (final row in bahanRows) {
                    final pkg = (row['packaging'] as String?) ?? '';
                    final qty = row['qty'] is int ? row['qty'] as int : int.tryParse('${row['qty']}') ?? 1;
                    if (pkg.isNotEmpty) await DbHelper().insertMenuStock(name, pkg, qty);
                  }

                  await widget.pos.syncCatalogUp();
                  if (mounted) {
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('✓ Menu $name berhasil disimpan!')));
                  }
                },
                child: const Text('Simpan Menu'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _confirmDeleteMenu(MenuItemModel item) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Hapus Menu ${item.name}?'),
        content: const Text('Menu ini akan dihapus dari daftar katalog kasir.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () async {
              if (item.id != null) {
                await DbHelper().deleteMenuItem(item.id!);
                await widget.pos.syncCatalogUp();
                if (mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('✓ Menu ${item.name} berhasil dihapus!')),
                  );
                }
              }
            },
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
  }

  void _showRestokDialog(PackagingModel pkg) {
    final qtyCtrl = TextEditingController(text: '50');
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('📦 Restok ${pkg.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Stok saat ini: ${pkg.stock} ${pkg.unit}', style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            TextField(
              controller: qtyCtrl,
              keyboardType: TextInputType.number,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Jumlah Penambahan (${pkg.unit})',
                hintText: 'Misal: 50',
                filled: true,
                fillColor: const Color(0xFFF1EFEB),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF7A5540), foregroundColor: Colors.white),
            onPressed: () async {
              final added = int.tryParse(qtyCtrl.text.trim()) ?? 0;
              if (added > 0 && pkg.id != null) {
                await DbHelper().updatePackagingStock(pkg.id!, added);
                // Catat ke tab Restok_Log di Google Sheet (kalau tersambung).
                final prefs = await SharedPreferences.getInstance();
                final sheetId = prefs.getString('spreadsheet_id') ?? '';
                if (sheetId.isNotEmpty) {
                  try {
                    final finalStock = pkg.stock + added;
                    await GoogleSheetService()
                        .logRestokToSheet(sheetId, pkg.name, added, pkg.unit, finalStock);
                  } catch (e) {
                    debugPrint('Log restok ke Sheet gagal: $e');
                  }
                }
                await widget.pos.syncCatalogUp();
                if (mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('✓ Stok ${pkg.name} berhasil ditambah +$added ${pkg.unit}!')),
                  );
                }
              }
            },
            child: const Text('Tambah Stok'),
          ),
        ],
      ),
    );
  }

  void _showVoucherDialog({VoucherModel? itemToEdit}) {
    final nameCtrl = TextEditingController(text: itemToEdit?.name ?? '');
    final valCtrl = TextEditingController(text: itemToEdit != null ? itemToEdit.value.toString() : '');
    final kuotaCtrl = TextEditingController(text: itemToEdit != null ? (itemToEdit.kuota?.toString() ?? '') : '100');
    String type = itemToEdit?.type ?? 'PERCENT';
    bool active = itemToEdit?.active ?? true;

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          title: Text(itemToEdit == null ? '🎟️ Tambah Voucher' : '✏️ Edit Voucher: ${itemToEdit.name}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Kode / Nama Voucher', hintText: 'Misal: SENYAWA10', filled: true, fillColor: Color(0xFFF1EFEB)),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: type,
                  decoration: const InputDecoration(labelText: 'Tipe Diskon', filled: true, fillColor: Color(0xFFF1EFEB)),
                  items: const [
                    DropdownMenuItem(value: 'PERCENT', child: Text('Persentase (%)')),
                    DropdownMenuItem(value: 'FIXED', child: Text('Potongan Tunai (Rp)')),
                  ],
                  onChanged: (val) => setDlgState(() => type = val!),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: valCtrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: type == 'PERCENT' ? 'Nilai Diskon (%)' : 'Nilai Diskon (Rp)', hintText: type == 'PERCENT' ? '10' : '5000', filled: true, fillColor: const Color(0xFFF1EFEB)),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: kuotaCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Kuota Penggunaan', hintText: 'Misal: 100', filled: true, fillColor: Color(0xFFF1EFEB)),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF7A5540), foregroundColor: Colors.white),
              onPressed: () async {
                final name = nameCtrl.text.trim();
                final val = int.tryParse(valCtrl.text.trim()) ?? 0;
                final kuota = int.tryParse(kuotaCtrl.text.trim());

                if (name.isNotEmpty && val > 0) {
                  final v = VoucherModel(
                    id: itemToEdit?.id,
                    name: name,
                    type: type,
                    value: val,
                    active: active,
                    kuota: kuota,
                    usedCount: itemToEdit?.usedCount ?? 0,
                  );
                  if (itemToEdit == null) {
                    await DbHelper().insertVoucher(v);
                  } else {
                    await DbHelper().updateVoucher(v);
                  }
                  await widget.pos.syncCatalogUp();
                  if (mounted) {
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('✓ Voucher $name berhasil disimpan!')));
                  }
                }
              },
              child: const Text('Simpan Voucher'),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDeleteVoucher(VoucherModel v) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Hapus Voucher ${v.name}?'),
        content: const Text('Voucher ini akan dihapus permanen.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () async {
              if (v.id != null) {
                await DbHelper().deleteVoucher(v.id!);
                await widget.pos.syncCatalogUp();
                if (mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('✓ Voucher ${v.name} berhasil dihapus!')));
                }
              }
            },
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
  }

  void _showReceiptSettingsDialog() async {
    final prefs = await SharedPreferences.getInstance();
    final headerCtrl = TextEditingController(text: prefs.getString('receipt_header') ?? 'Ruang Senyawa Coffee\nInstagram: @r_senyawa');
    final footerCtrl = TextEditingController(text: prefs.getString('receipt_footer') ?? 'WiFi      : Ruang Senyawa\nPassword  : followIGdulu\n\nTerima kasih sudah menjadi bagian \ndari cerita di Ruang Senyawa.');
    String size = prefs.getString('paper_size') ?? _paperSize;
    bool showLogo = prefs.getBool('receipt_show_logo') ?? true;
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          title: const Text('🧾 Setelan Struk'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Header (tulisan atas struk):', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                const SizedBox(height: 4),
                TextField(controller: headerCtrl, maxLines: 3, decoration: const InputDecoration(filled: true, fillColor: Color(0xFFF1EFEB), hintText: 'Nama cafe / IG')),
                const SizedBox(height: 10),
                const Text('Footer (tulisan bawah struk):', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                const SizedBox(height: 4),
                TextField(controller: footerCtrl, maxLines: 5, decoration: const InputDecoration(filled: true, fillColor: Color(0xFFF1EFEB), hintText: 'WiFi, ucapan terima kasih, dll')),
                const SizedBox(height: 10),
                const Text('Ukuran kertas:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                const SizedBox(height: 4),
                Row(children: [
                  ChoiceChip(label: const Text('58mm'), selected: size == '58mm', onSelected: (_) => setDlgState(() => size = '58mm')),
                  const SizedBox(width: 8),
                  ChoiceChip(label: const Text('80mm'), selected: size == '80mm', onSelected: (_) => setDlgState(() => size = '80mm')),
                ]),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Tampilkan logo di struk', style: TextStyle(fontSize: 13)),
                  value: showLogo,
                  activeThumbColor: const Color(0xFF7A5540),
                  onChanged: (v) => setDlgState(() => showLogo = v),
                ),
                const Text('Logo tampil di preview struk. Cetak logo ke printer thermal (bitmap) menyusul.', style: TextStyle(fontSize: 10, color: Colors.grey)),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF356A58), foregroundColor: Colors.white),
              onPressed: () async {
                await prefs.setString('receipt_header', headerCtrl.text);
                await prefs.setString('receipt_footer', footerCtrl.text);
                await prefs.setString('paper_size', size);
                await prefs.setBool('receipt_show_logo', showLogo);
                if (mounted) setState(() => _paperSize = size);
                if (mounted) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✓ Setelan struk disimpan')));
                }
              },
              child: const Text('Simpan'),
            ),
          ],
        ),
      ),
    );
  }

  void _showPrinterSettingsDialog() async {
    final nameCtrl = TextEditingController(text: _printerName);
    String size = _paperSize;
    bool autoP = _autoPrint;
    final List<String> popularPrinters = [
      'POS-5802',
      'RPP02N',
      'PT-210',
      'BT-Printer',
      'InnerPrinter',
      'MTP-II',
      'Thermal 58mm',
    ];

    List<Map<String, String>> pairedDevicesFromPhone = [];

    try {
      const platform = MethodChannel('id.ruangsenyawa.pos/printer');
      final res = await platform.invokeMethod('getPairedDevices');
      if (res is List) {
        pairedDevicesFromPhone = res.map((e) => Map<String, String>.from(e as Map)).toList();
      }
    } catch (_) {}

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          title: const Text('🖨️ Setelan Printer Bluetooth Native'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Pilih / Ketik Nama Printer Bluetooth HP:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                const SizedBox(height: 6),
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Nama Perangkat / MAC Address',
                    hintText: 'Misal: POS-5802 atau RPP02N',
                    filled: true,
                    fillColor: Color(0xFFF1EFEB),
                  ),
                ),
                const SizedBox(height: 8),

                // Dynamic Live Paired Devices from Phone
                if (pairedDevicesFromPhone.isNotEmpty) ...[
                  const Text('📱 Perangkat Bluetooth Tersanding di HP Bro (Live Native):', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF356A58))),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: pairedDevicesFromPhone.map((dev) {
                      final pName = dev['name'] ?? 'Unknown';
                      final pAddr = dev['address'] ?? '';
                      final bool isSelected = nameCtrl.text.trim().toUpperCase() == pName.toUpperCase() || nameCtrl.text.trim() == pAddr;
                      return ChoiceChip(
                        avatar: const Icon(Icons.bluetooth_connected, size: 14, color: Color(0xFF356A58)),
                        label: Text('$pName ($pAddr)', style: const TextStyle(fontSize: 11)),
                        selected: isSelected,
                        selectedColor: const Color(0xFFB7F1DC),
                        onSelected: (sel) {
                          if (sel) {
                            setDlgState(() {
                              nameCtrl.text = pName;
                            });
                          }
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 10),
                ],

                const Text('Perangkat Bluetooth Populer Kasir:', style: TextStyle(fontSize: 11, color: Colors.grey)),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  children: popularPrinters.map((p) {
                    final bool isSelected = nameCtrl.text.trim().toUpperCase() == p.toUpperCase();
                    return ChoiceChip(
                      label: Text(p, style: const TextStyle(fontSize: 11)),
                      selected: isSelected,
                      selectedColor: const Color(0xFFB7F1DC),
                      onSelected: (sel) {
                        if (sel) {
                          setDlgState(() {
                            nameCtrl.text = p;
                          });
                        }
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: size,
                  decoration: const InputDecoration(labelText: 'Ukuran Kertas Struk', filled: true, fillColor: Color(0xFFF1EFEB)),
                  items: const [
                    DropdownMenuItem(value: '58mm', child: Text('58mm Thermal (Mini/Kasir Standard)')),
                    DropdownMenuItem(value: '80mm', child: Text('80mm Thermal (Standar Dapur)')),
                  ],
                  onChanged: (val) => setDlgState(() => size = val!),
                ),
                const SizedBox(height: 10),
                SwitchListTile(
                  title: const Text('Cetak Struk Otomatis Selesai Transaksi', style: TextStyle(fontSize: 13)),
                  value: autoP,
                  activeThumbColor: const Color(0xFF7A5540),
                  onChanged: (val) => setDlgState(() => autoP = val),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF356A58), foregroundColor: Colors.white),
              onPressed: () async {
                final pName = nameCtrl.text.trim();
                final prefs = await SharedPreferences.getInstance();
                await prefs.setString('printer_name', pName.isEmpty ? 'Thermal 58mm' : pName);
                await prefs.setString('paper_size', size);
                await prefs.setBool('auto_print', autoP);

                setState(() {
                  _printerName = pName.isEmpty ? 'Thermal 58mm' : pName;
                  _paperSize = size;
                  _autoPrint = autoP;
                });

                if (mounted) {
                  Navigator.pop(ctx);
                  _showTestPrintDialog();
                }
              },
              icon: const Icon(Icons.print, size: 16),
              label: const Text('Simpan & Tes Cetak'),
            ),
          ],
        ),
      ),
    );
  }

  void _showTestPrintDialog() {
    final now = DateTime.now();
    final sampleTrx = TransactionModel(
      id: 'test_123',
      code: 'TRX-TEST-001',
      createdAt: now,
      businessDate: DateFormat('yyyy-MM-dd').format(now),
      cashierName: widget.pos.activeCashierDisplay,
      orderType: 'DINE_IN',
      paymentMethod: 'CASH',
      subtotal: 28000,
      discountAmount: 0,
      totalAmount: 28000,
      cashReceived: 50000,
      changeAmount: 22000,
    );

    final sampleItems = [
      CartItem(
        menu: MenuItemModel(id: 1, name: 'Kopi Susu Senyawa', category: 'KOPI', price: 13000, cost: 5000, active: true, sortOrder: 0),
        selectedVariants: ['Dingin (Es)'],
        quantity: 1,
      ),
      CartItem(
        menu: MenuItemModel(id: 2, name: 'Kopi Susu Oat', category: 'KOPI', price: 15000, cost: 5000, active: true, sortOrder: 0),
        selectedVariants: ['Dingin (Es)', '2 Shot (+3k)'],
        quantity: 1,
      ),
    ];

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ReceiptScreen(transaction: sampleTrx, items: sampleItems),
      ),
    );
  }

  void _showChangePinDialog() {
    final oldPinCtrl = TextEditingController();
    final newPinCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('🔑 Ganti PIN Admin'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: oldPinCtrl,
              obscureText: true,
              keyboardType: TextInputType.visiblePassword,
              decoration: const InputDecoration(labelText: 'PIN / Password Lama', hintText: '1234', filled: true, fillColor: Color(0xFFF1EFEB)),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: newPinCtrl,
              obscureText: true,
              keyboardType: TextInputType.visiblePassword,
              decoration: const InputDecoration(labelText: 'PIN / Password Baru (Bebas 4, 6, 7, 8+ Digit)', hintText: 'Misal: 567890 atau 12345678', filled: true, fillColor: Color(0xFFF1EFEB)),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF7A5540), foregroundColor: Colors.white),
            onPressed: () async {
              if (widget.settings.verifyPin(oldPinCtrl.text.trim())) {
                final success = await widget.settings.setAdminPin(newPinCtrl.text.trim());
                if (mounted) {
                  Navigator.pop(context);
                  if (success) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✓ PIN / Password Admin Berhasil Diperbarui!')));
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('❌ PIN / Password tidak boleh kosong!')));
                  }
                }
              } else {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('❌ PIN / Password Lama Salah!')));
              }
            },
            child: const Text('Ganti PIN'),
          ),
        ],
      ),
    );
  }

  void _showAddEmployeeDialog() {
    final nameCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('👤 Tambah Karyawan Baru'),
        content: TextField(
          controller: nameCtrl,
          decoration: const InputDecoration(labelText: 'Nama Karyawan', hintText: 'Misal: Dina', filled: true, fillColor: Color(0xFFF1EFEB)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF7A5540), foregroundColor: Colors.white),
            onPressed: () async {
              final name = nameCtrl.text.trim();
              if (name.isNotEmpty) {
                await DbHelper().insertEmployee(name);
                await _loadInitialData();
                if (mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('✓ Karyawan $name berhasil ditambahkan!')));
                }
              }
            },
            child: const Text('Tambah'),
          ),
        ],
      ),
    );
  }

  void _showManageVariantsDialog(MenuItemModel item) {
    // Form "buat grup baru"
    final newGroupCtrl = TextEditingController();
    String newGroupType = 'SINGLE';
    bool newGroupReq = true;

    // State form "tambah pilihan" per grup (persist antar rebuild).
    final Map<String, TextEditingController> optNameCtrls = {};
    final Map<String, TextEditingController> optPriceCtrls = {};
    final Map<String, String?> optPkgSel = {};
    final Map<String, int> optQtySel = {};
    // State "tambah bahan ke opsi yang sudah ada" — key: "grup||opsi".
    final Map<String, String?> stkPkgSel = {};
    final Map<String, int> stkQtySel = {};

    showDialog(
      context: context,
      builder: (dlgCtx) => StatefulBuilder(
        builder: (ctx, setDlgState) {
          return AlertDialog(
            title: Text('🎛️ Atur Varian: ${item.name}'),
            content: SizedBox(
              width: double.maxFinite,
              child: FutureBuilder<List<Map<String, dynamic>>>(
                future: DbHelper().getVariantTree(item.name),
                builder: (fCtx, snap) {
                  if (!snap.hasData) {
                    return const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()));
                  }
                  final tree = snap.data!;
                  final packs = widget.pos.packagings;
                  return SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Grup varian menu ini:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                        const SizedBox(height: 6),
                        if (tree.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 6),
                            child: Text('Belum ada grup. Bikin di bawah (mis. "Suhu", "Shot").', style: TextStyle(fontSize: 11, color: Colors.grey)),
                          ),
                        ...tree.map((node) {
                          final VariantGroupModel g = node['group'] as VariantGroupModel;
                          final List options = node['options'] as List;
                          final gName = g.groupName;
                          final nameC = optNameCtrls.putIfAbsent(gName, () => TextEditingController());
                          final priceC = optPriceCtrls.putIfAbsent(gName, () => TextEditingController(text: '0'));
                          final selPkg = optPkgSel[gName];
                          final qty = optQtySel[gName] ?? 1;
                          return Card(
                            color: const Color(0xFFF5F3F0),
                            margin: const EdgeInsets.only(bottom: 10),
                            child: Padding(
                              padding: const EdgeInsets.all(10),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Header grup
                                  Row(
                                    children: [
                                      Expanded(child: Text(gName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14))),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                        decoration: BoxDecoration(color: const Color(0xFF7A5540), borderRadius: BorderRadius.circular(4)),
                                        child: Text('${g.type == "MULTI" ? "Boleh banyak" : "Pilih 1"} · ${g.required ? "Wajib" : "Opsional"}', style: const TextStyle(fontSize: 9, color: Colors.white)),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                                        tooltip: 'Hapus grup',
                                        onPressed: () async {
                                          await DbHelper().deleteVariantGroup(item.name, gName);
                                          setDlgState(() {});
                                        },
                                      ),
                                    ],
                                  ),
                                  const Divider(height: 12),
                                  // Daftar pilihan
                                  if (options.isEmpty)
                                    const Padding(padding: EdgeInsets.only(bottom: 6), child: Text('Belum ada pilihan.', style: TextStyle(fontSize: 11, color: Colors.grey)))
                                  else
                                    ...options.map((op) {
                                      final VariantOptionModel o = op['option'] as VariantOptionModel;
                                      final List stocks = op['stocks'] as List;
                                      final okey = '$gName||${o.optionName}';
                                      final sPkg = stkPkgSel[okey];
                                      final sQty = stkQtySel[okey] ?? 1;
                                      return Container(
                                        margin: const EdgeInsets.only(bottom: 6),
                                        padding: const EdgeInsets.all(6),
                                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(6)),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            // Nama opsi + harga + hapus opsi
                                            Row(children: [
                                              Expanded(child: Text.rich(TextSpan(children: [
                                                TextSpan(text: '• ${o.optionName}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.black87)),
                                                if (o.priceDelta != 0) TextSpan(text: '  +Rp${o.priceDelta}', style: const TextStyle(fontSize: 11, color: Color(0xFF356A58))),
                                              ]))),
                                              InkWell(
                                                onTap: () async {
                                                  await DbHelper().deleteVariantOption(item.name, gName, o.optionName);
                                                  setDlgState(() {});
                                                },
                                                child: const Padding(padding: EdgeInsets.all(4), child: Icon(Icons.delete_outline, size: 17, color: Colors.red)),
                                              ),
                                            ]),
                                            // Daftar bahan opsi ini (tiap bisa dihapus)
                                            ...stocks.map((s) => Padding(
                                              padding: const EdgeInsets.only(left: 6, top: 2),
                                              child: Row(children: [
                                                const Icon(Icons.science_outlined, size: 13, color: Colors.brown),
                                                const SizedBox(width: 4),
                                                Expanded(child: Text('${s['packaging_name']} (${s['qty']}x)', style: const TextStyle(fontSize: 11, color: Colors.brown))),
                                                InkWell(
                                                  onTap: () async {
                                                    await DbHelper().deleteVariantOptionStockById(s['id'] as int);
                                                    setDlgState(() {});
                                                  },
                                                  child: const Padding(padding: EdgeInsets.all(2), child: Icon(Icons.close, size: 13, color: Colors.redAccent)),
                                                ),
                                              ]),
                                            )),
                                            // Tambah bahan ke OPSI INI (mis. Panas → cup panas)
                                            Padding(
                                              padding: const EdgeInsets.only(left: 6, top: 4),
                                              child: Row(children: [
                                                Expanded(
                                                  child: DropdownButtonFormField<String>(
                                                    value: sPkg,
                                                    isDense: true,
                                                    decoration: const InputDecoration(isDense: true, filled: true, fillColor: Color(0xFFF5F3F0), contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 4)),
                                                    hint: const Text('+ bahan opsi', style: TextStyle(fontSize: 10), overflow: TextOverflow.ellipsis),
                                                    items: packs.map((p) => DropdownMenuItem(value: p.name, child: Text(p.name, style: const TextStyle(fontSize: 10), overflow: TextOverflow.ellipsis))).toList(),
                                                    onChanged: (v) => setDlgState(() => stkPkgSel[okey] = v),
                                                  ),
                                                ),
                                                InkWell(
                                                  onTap: () => setDlgState(() { if (sQty > 1) stkQtySel[okey] = sQty - 1; }),
                                                  child: const Padding(padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2), child: Icon(Icons.remove, size: 15)),
                                                ),
                                                Text('$sQty', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                                                InkWell(
                                                  onTap: () => setDlgState(() => stkQtySel[okey] = sQty + 1),
                                                  child: const Padding(padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2), child: Icon(Icons.add, size: 15)),
                                                ),
                                                const SizedBox(width: 2),
                                                InkWell(
                                                  onTap: (sPkg == null || sPkg.isEmpty) ? null : () async {
                                                    await DbHelper().insertVariantOptionStock(item.name, gName, o.optionName, sPkg, sQty);
                                                    stkPkgSel[okey] = null;
                                                    stkQtySel[okey] = 1;
                                                    setDlgState(() {});
                                                  },
                                                  child: const Padding(padding: EdgeInsets.all(2), child: Icon(Icons.check_circle, size: 18, color: Color(0xFF356A58))),
                                                ),
                                              ]),
                                            ),
                                          ],
                                        ),
                                      );
                                    }),
                                  const SizedBox(height: 6),
                                  // Form tambah pilihan
                                  Row(
                                    children: [
                                      Expanded(flex: 3, child: TextField(controller: nameC, decoration: const InputDecoration(isDense: true, hintText: 'Nama pilihan (mis. Panas)', filled: true, fillColor: Colors.white, contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8)))),
                                      const SizedBox(width: 6),
                                      Expanded(flex: 2, child: TextField(controller: priceC, keyboardType: TextInputType.number, decoration: const InputDecoration(isDense: true, hintText: '+Harga', filled: true, fillColor: Colors.white, contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8)))),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: DropdownButtonFormField<String>(
                                          value: selPkg,
                                          isDense: true,
                                          decoration: const InputDecoration(isDense: true, filled: true, fillColor: Colors.white, contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 4)),
                                          hint: const Text('Bahan (opsional)', style: TextStyle(fontSize: 10), overflow: TextOverflow.ellipsis),
                                          items: [
                                            const DropdownMenuItem<String>(value: '', child: Text('— Tanpa bahan —', style: TextStyle(fontSize: 10), overflow: TextOverflow.ellipsis)),
                                            ...packs.map((p) => DropdownMenuItem(value: p.name, child: Text(p.name, style: const TextStyle(fontSize: 10), overflow: TextOverflow.ellipsis))),
                                          ],
                                          onChanged: (v) => setDlgState(() => optPkgSel[gName] = v),
                                        ),
                                      ),
                                      InkWell(
                                        onTap: () => setDlgState(() { if (qty > 1) optQtySel[gName] = qty - 1; }),
                                        child: const Padding(padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2), child: Icon(Icons.remove, size: 15)),
                                      ),
                                      Text('$qty', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                                      InkWell(
                                        onTap: () => setDlgState(() => optQtySel[gName] = qty + 1),
                                        child: const Padding(padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2), child: Icon(Icons.add, size: 15)),
                                      ),
                                    ],
                                  ),
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: TextButton.icon(
                                      onPressed: () async {
                                        final oName = nameC.text.trim();
                                        if (oName.isEmpty) return;
                                        final delta = int.tryParse(priceC.text.trim()) ?? 0;
                                        await DbHelper().insertVariantOption(item.name, gName, oName, delta);
                                        if (selPkg != null && selPkg.isNotEmpty) {
                                          await DbHelper().insertVariantOptionStock(item.name, gName, oName, selPkg, qty);
                                        }
                                        nameC.clear();
                                        priceC.text = '0';
                                        optPkgSel[gName] = null;
                                        optQtySel[gName] = 1;
                                        setDlgState(() {});
                                      },
                                      icon: const Icon(Icons.add, size: 16),
                                      label: const Text('Tambah pilihan', style: TextStyle(fontSize: 12)),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }),
                        const Divider(height: 24),
                        const Text('➕ Buat grup baru:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                        const SizedBox(height: 6),
                        TextField(controller: newGroupCtrl, decoration: const InputDecoration(labelText: 'Nama grup (mis. Suhu, Shot, Topping)', filled: true, fillColor: Color(0xFFF1EFEB))),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                value: newGroupType,
                                isDense: true,
                                decoration: const InputDecoration(labelText: 'Tipe', filled: true, fillColor: Color(0xFFF1EFEB)),
                                items: const [
                                  DropdownMenuItem(value: 'SINGLE', child: Text('Pilih 1', style: TextStyle(fontSize: 12))),
                                  DropdownMenuItem(value: 'MULTI', child: Text('Boleh banyak', style: TextStyle(fontSize: 12))),
                                ],
                                onChanged: (v) => setDlgState(() => newGroupType = v!),
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Text('Wajib', style: TextStyle(fontSize: 12)),
                            Switch(value: newGroupReq, onChanged: (v) => setDlgState(() => newGroupReq = v)),
                          ],
                        ),
                        const SizedBox(height: 6),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF7A5540), foregroundColor: Colors.white),
                            onPressed: () async {
                              final gName = newGroupCtrl.text.trim();
                              if (gName.isEmpty) return;
                              await DbHelper().insertVariantGroup(item.name, gName, newGroupType, newGroupReq);
                              newGroupCtrl.clear();
                              setDlgState(() {});
                            },
                            icon: const Icon(Icons.add, size: 16),
                            label: const Text('Buat Grup'),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            actions: [
              TextButton(onPressed: () { Navigator.pop(dlgCtx); setState(() {}); }, child: const Text('Selesai')),
            ],
          );
        },
      ),
    );
  }
}
