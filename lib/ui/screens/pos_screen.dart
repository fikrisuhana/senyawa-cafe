import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../models/models.dart';
import '../../providers/pos_provider.dart';
import '../../providers/settings_provider.dart';
import '../../services/db_helper.dart';
import '../widgets/variant_sheet.dart';
import 'receipt_screen.dart';
import 'recap_screen.dart';
import 'absen_screen.dart';
import 'admin_hub_screen.dart';

class PosScreen extends StatefulWidget {
  const PosScreen({super.key});

  @override
  State<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends State<PosScreen> {
  int _currentBottomNav = 0;

  @override
  Widget build(BuildContext context) {
    final pos = Provider.of<PosProvider>(context);
    final settings = Provider.of<SettingsProvider>(context);
    final currencyFormatter = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp', decimalDigits: 0);

    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isTablet = constraints.maxWidth >= 600;

        final bool isDark = Theme.of(context).brightness == Brightness.dark;

        return Scaffold(
          appBar: AppBar(
            backgroundColor: isDark ? const Color(0xFF1E1E1E) : const Color(0xFF1A73E8),
            foregroundColor: Colors.white,
            elevation: 2,
            title: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1.5),
                    image: const DecorationImage(
                      image: AssetImage('assets/seed/logo.jpg'),
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Ruang Senyawa',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                        overflow: TextOverflow.ellipsis,
                      ),
                      InkWell(
                        onTap: () => _showSelectCashierDialog(context, pos),
                        child: Text(
                          '👤 Kasir: ${pos.activeCashierDisplay} ✏️',
                          style: const TextStyle(fontSize: 10, color: Colors.white70, fontWeight: FontWeight.bold),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.history, color: Colors.white),
                tooltip: 'Riwayat Transaksi Hari Ini',
                onPressed: () => _showHistoryDialog(context, pos, currencyFormatter),
              ),
              Container(
                margin: const EdgeInsets.only(right: 14),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF2D2D2D) : const Color(0xFFE8F0FE),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: pos.isSyncing ? Colors.amber : const Color(0xFF0F9D58),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      pos.syncStatusText,
                      style: TextStyle(
                        fontSize: 10,
                        color: isDark ? Colors.white70 : const Color(0xFF174EA6),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          body: pos.isLoading
              ? const Center(child: CircularProgressIndicator())
              : (isTablet && _currentBottomNav == 0)
                  // Tablet + tab Kasir = split view (menu kiri, keranjang kanan).
                  ? _buildTabletSplitView(pos, settings, currencyFormatter)
                  // Tablet tab lain / HP = layar penuh biasa.
                  : _buildPhoneContent(pos, settings, currencyFormatter),
          bottomNavigationBar: BottomNavigationBar(
            currentIndex: _currentBottomNav,
            selectedItemColor: isDark ? const Color(0xFF4796FF) : const Color(0xFF1A73E8),
            unselectedItemColor: Colors.grey.shade600,
            type: BottomNavigationBarType.fixed,
            onTap: (index) {
              if (index == 3 && !settings.isAdminUnlocked) {
                _showPinDialog(context, settings);
              } else {
                setState(() => _currentBottomNav = index);
              }
            },
            items: [
              const BottomNavigationBarItem(icon: Icon(Icons.receipt_long), label: 'Kasir'),
              const BottomNavigationBarItem(icon: Icon(Icons.bar_chart), label: 'Rekap'),
              const BottomNavigationBarItem(icon: Icon(Icons.access_time), label: 'Absen'),
              BottomNavigationBarItem(
                icon: Icon(settings.isAdminUnlocked ? Icons.lock_open : Icons.lock),
                label: 'Admin',
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPhoneContent(PosProvider pos, SettingsProvider settings, NumberFormat currencyFormatter) {
    if (_currentBottomNav == 1) return RecapScreen(pos: pos);
    if (_currentBottomNav == 2) return const AbsenScreen();
    if (_currentBottomNav == 3) return AdminHubScreen(settings: settings, pos: pos, onLockAdmin: () => setState(() => _currentBottomNav = 0));

    return Column(
      children: [
        _buildSearchBar(pos),
        _buildCategoryChips(pos),
        Expanded(child: _buildMenuGrid(pos, currencyFormatter)),
        _buildCashierSelectorBar(pos),
        if (pos.cartItems.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF1E1E1E) : const Color(0xFF1A73E8),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, -2))],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('🛒 ${pos.cartItems.length} Item Pesanan', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13), overflow: TextOverflow.ellipsis),
                      Text(currencyFormatter.format(pos.totalAmount), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15), overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFB7F1DC),
                    foregroundColor: const Color(0xFF00201A),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: () => _showPhoneCartSheet(context, pos, settings, currencyFormatter),
                  child: const Text('Lihat Keranjang & Bayar ›', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
      ],
    );
  }

  // --- TABLET SPLIT VIEW: menu (kiri) + keranjang permanen (kanan) ---
  Widget _buildTabletSplitView(PosProvider pos, SettingsProvider settings, NumberFormat currencyFormatter) {
    return Row(
      children: [
        Expanded(
          flex: 13,
          child: Column(
            children: [
              _buildSearchBar(pos),
              _buildCategoryChips(pos),
              Expanded(child: _buildMenuGrid(pos, currencyFormatter)),
              _buildCashierSelectorBar(pos),
            ],
          ),
        ),
        Expanded(
          flex: 10,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF1A1A1A) : Colors.white,
              border: Border(left: BorderSide(color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF333333) : const Color(0xFFE0E0E0))),
            ),
            child: _buildCartPanel(pos, settings, currencyFormatter),
          ),
        ),
      ],
    );
  }

  Widget _buildSearchBar(PosProvider pos) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: TextField(
        onChanged: (val) => pos.setSearchQuery(val),
        decoration: InputDecoration(
          hintText: '🔍 Cari menu cepat...',
          suffixIcon: pos.searchQuery.isNotEmpty
              ? IconButton(icon: const Icon(Icons.clear), onPressed: () => pos.setSearchQuery(''))
              : null,
          filled: true,
          fillColor: const Color(0xFFF1EFEB),
          contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(28), borderSide: BorderSide.none),
        ),
      ),
    );
  }

  Widget _buildCategoryChips(PosProvider pos) {
    final categories = ['SEMUA', 'KOPI', 'NON-KOPI', 'MAKANAN'];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: categories.map((cat) {
          final isSel = pos.selectedCategory == cat;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(cat),
              selected: isSel,
              selectedColor: const Color(0xFFB7F1DC),
              labelStyle: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 11,
                color: isSel ? const Color(0xFF00201A) : const Color(0xFF51443B),
              ),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              onSelected: (_) => pos.setSelectedCategory(cat),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildMenuGrid(PosProvider pos, NumberFormat currencyFormatter) {
    final items = pos.filteredMenuItems;
    final double width = MediaQuery.of(context).size.width;
    // Tablet split-view: kanan ada panel → kolom menyesuaikan lebar kiri saja.
    // HP: 2 kolom. Tablet kecil: 3. Tablet besar: 4.
    int crossAxisCount = 2;
    double childAspectRatio = 1.65;
    if (width >= 900) {
      crossAxisCount = 4;
      childAspectRatio = 1.5;
    } else if (width >= 600) {
      crossAxisCount = 3;
      childAspectRatio = 1.58;
    }

    return GridView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        childAspectRatio: childAspectRatio,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];

        // Hitung berapa item menu ini yang ada di keranjang
        final int inCart = pos.cartItems
            .where((c) => c.menu.name == item.name)
            .fold(0, (sum, c) => sum + c.quantity);

        return Card(
          elevation: 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: inCart > 0 ? const Color(0xFF0F9D58) : Colors.transparent,
              width: inCart > 0 ? 1.5 : 0,
            ),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () async {
              final cat = item.category.toUpperCase();
              final groups = await DbHelper().getVariantGroupsForMenu(item.name);

              if (groups.isEmpty && cat != 'KOPI' && cat != 'NON-KOPI') {
                pos.addToCart(item);
                return;
              }

              if (context.mounted) {
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (_) => VariantSheet(
                    menuItem: item,
                    onAdd: (variants, extra, note) {
                      pos.addToCart(item, selectedVariants: variants, extraPrice: extra, note: note);
                    },
                  ),
                );
              }
            },
            child: Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        item.category.toUpperCase(),
                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.grey),
                      ),
                      Text(
                        item.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, height: 1.15),
                      ),
                      Text(
                        currencyFormatter.format(item.price),
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF0F9D58)),
                      ),
                      Row(
                        children: [
                          if (item.name.contains('Oat') || item.name.contains('Gula Aren')) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(color: const Color(0xFFE8F0FE), borderRadius: BorderRadius.circular(4)),
                              child: const Text('+varian', style: TextStyle(fontSize: 9, color: Color(0xFF1A73E8), fontWeight: FontWeight.bold)),
                            ),
                            const SizedBox(width: 4),
                          ],
                          // Estimasi porsi real dari stok bahan (bukan angka hardcode).
                          FutureBuilder<int?>(
                            future: DbHelper().estimateMenuPortions(item.name),
                            builder: (ctx, snap) {
                              if (!snap.hasData || snap.data == null) {
                                return const Text('stok ∞', style: TextStyle(fontSize: 10, color: Colors.grey));
                              }
                              final portions = snap.data!;
                              final isLow = portions <= 5;
                              return Text(
                                portions == 0 ? '⚠️ habis' : 'sisa $portions',
                                style: TextStyle(fontSize: 10, color: isLow ? Colors.red : Colors.grey),
                              );
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (inCart > 0)
                  Positioned(
                    right: 8,
                    top: 8,
                    child: Container(
                      padding: const EdgeInsets.all(5),
                      decoration: const BoxDecoration(
                        color: Color(0xFF356A58),
                        shape: BoxShape.circle,
                      ),
                      constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                      child: Center(
                        child: Text(
                          '$inCart',
                          style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCartPanel(PosProvider pos, SettingsProvider settings, NumberFormat currencyFormatter, {StateSetter? setSheetState}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Pesanan (${pos.cartItems.length} item)', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            TextButton(
              onPressed: () {
                pos.clearCart();
                if (setSheetState != null) setSheetState(() {});
              },
              child: const Text('Reset', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        const SizedBox(height: 6),

        // Segmented Dine In / Takeaway Buttons
        Row(
          children: [
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () {
                  pos.setOrderType('DINE_IN');
                  if (setSheetState != null) setSheetState(() {});
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: pos.orderType == 'DINE_IN' ? const Color(0xFFB7F1DC) : const Color(0xFFF1EFEB),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: pos.orderType == 'DINE_IN' ? const Color(0xFF356A58) : Colors.transparent,
                      width: 1.5,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      '🍽️ Di tempat',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: pos.orderType == 'DINE_IN' ? const Color(0xFF00201A) : const Color(0xFF51443B),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () {
                  pos.setOrderType('TAKEAWAY');
                  if (setSheetState != null) setSheetState(() {});
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: pos.orderType == 'TAKEAWAY' ? const Color(0xFFB7F1DC) : const Color(0xFFF1EFEB),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: pos.orderType == 'TAKEAWAY' ? const Color(0xFF356A58) : Colors.transparent,
                      width: 1.5,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      '🥡 Bungkus',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: pos.orderType == 'TAKEAWAY' ? const Color(0xFF00201A) : const Color(0xFF51443B),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // Cart Items List
        Expanded(
          child: ListView.separated(
            itemCount: pos.cartItems.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final c = pos.cartItems[index];
              return ListTile(
                contentPadding: EdgeInsets.zero,
                title: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(c.menu.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    Text(currencyFormatter.format(c.totalPrice), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  ],
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (c.selectedVariants.isNotEmpty)
                      Text(c.variantDescription, style: const TextStyle(fontSize: 10, color: Colors.grey)),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        InkWell(
                          onTap: () {
                            showModalBottomSheet(
                              context: context,
                              isScrollControlled: true,
                              backgroundColor: Colors.transparent,
                              builder: (_) => VariantSheet(
                                menuItem: c.menu,
                                onAdd: (variants, extra, note) {
                                  pos.updateQuantity(index, -c.quantity);
                                  pos.addToCart(c.menu, selectedVariants: variants, extraPrice: extra, note: note);
                                  if (setSheetState != null) setSheetState(() {});
                                },
                              ),
                            );
                          },
                          child: const Text('Edit Varian', style: TextStyle(fontSize: 10, color: Color(0xFF7A5540), fontWeight: FontWeight.bold)),
                        ),
                        Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.remove_circle_outline, size: 18),
                              onPressed: () {
                                pos.updateQuantity(index, -1);
                                if (setSheetState != null) setSheetState(() {});
                              },
                            ),
                            Text('${c.quantity}', style: const TextStyle(fontWeight: FontWeight.bold)),
                            IconButton(
                              icon: const Icon(Icons.add_circle_outline, size: 18),
                              onPressed: () {
                                pos.updateQuantity(index, 1);
                                if (setSheetState != null) setSheetState(() {});
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        ),

        // Voucher / Diskon selector
        if (pos.vouchers.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(color: const Color(0xFFF5F3F0), borderRadius: BorderRadius.circular(12)),
            child: Row(
              children: [
                const Icon(Icons.confirmation_number_outlined, size: 18, color: Color(0xFF7A5540)),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButton<VoucherModel?>(
                    isExpanded: true,
                    underline: const SizedBox(),
                    hint: const Text('Pakai Voucher / Diskon', style: TextStyle(fontSize: 13)),
                    value: pos.selectedVoucher,
                    items: <DropdownMenuItem<VoucherModel?>>[
                      const DropdownMenuItem<VoucherModel?>(value: null, child: Text('— Tanpa Voucher —', style: TextStyle(fontSize: 13))),
                      ...pos.vouchers.map((v) => DropdownMenuItem<VoucherModel?>(
                            value: v,
                            child: Text(
                              '${v.name} (${v.type == 'PERCENT' ? '${v.value}%' : 'Rp${v.value}'})',
                              style: const TextStyle(fontSize: 13),
                              overflow: TextOverflow.ellipsis,
                            ),
                          )),
                    ],
                    onChanged: (v) {
                      pos.setSelectedVoucher(v);
                      if (setSheetState != null) setSheetState(() {});
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],

        // Payment Summary
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: const Color(0xFFF1EFEB), borderRadius: BorderRadius.circular(14)),
          child: Column(
            children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Subtotal', style: TextStyle(fontSize: 12)), Text(currencyFormatter.format(pos.subtotal), style: const TextStyle(fontSize: 12))]),
              if (pos.discountAmount > 0)
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Diskon', style: TextStyle(fontSize: 12, color: Color(0xFF7C5800))), Text('-${currencyFormatter.format(pos.discountAmount)}', style: const TextStyle(fontSize: 12, color: Color(0xFF7C5800)))]),
              const Divider(height: 10),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('TOTAL', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)), Text(currencyFormatter.format(pos.totalAmount), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF7A5540)))]),
            ],
          ),
        ),
        const SizedBox(height: 10),

        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF7A5540),
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(48),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          onPressed: pos.cartItems.isEmpty
              ? null
              : () => _showPaymentSheet(context, pos, currencyFormatter),
          child: const Text('Pilih Metode Bayar ›', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }

  void _showPhoneCartSheet(BuildContext context, PosProvider pos, SettingsProvider settings, NumberFormat currencyFormatter) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFFFFFFFF),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSheetState) => Container(
          height: 520,
          padding: const EdgeInsets.all(16),
          child: _buildCartPanel(pos, settings, currencyFormatter, setSheetState: setSheetState),
        ),
      ),
    );
  }

  // --- POPUP MODAL PEMBAYARAN LENGKAP (TUNAI / QRIS / TRANSFER & QUICK CASH) ---
  void _showPaymentSheet(BuildContext context, PosProvider pos, NumberFormat currencyFormatter) {
    final TextEditingController cashController = TextEditingController(
      text: pos.cashReceived > 0 ? pos.cashReceived.toString() : pos.totalAmount.toString(),
    );
    // Tangkap navigator halaman kasir SEBELUM buka sheet — biar push struk tak nyangkut di sheet.
    final navigator = Navigator.of(context);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFFFFFFFF),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('💳 Metode Pembayaran', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                      IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text('Total Tagihan: ${currencyFormatter.format(pos.totalAmount)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF7A5540))),
                  const SizedBox(height: 16),

                  // Pilihan Metode Bayar (dinamis dari Setup Sheet).
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: pos.paymentMethods.map((method) {
                      final bool isCash = pos.isCashMethod(method);
                      final icon = isCash ? '💵' : (method.toLowerCase().contains('qris') ? '📲' : '🏦');
                      return ChoiceChip(
                        label: Text('$icon $method', style: const TextStyle(fontWeight: FontWeight.bold)),
                        selected: pos.paymentMethod == method,
                        selectedColor: const Color(0xFFB7F1DC),
                        onSelected: (_) {
                          pos.setPaymentMethod(method);
                          if (isCash) {
                            pos.setCashReceived(pos.totalAmount);
                            cashController.text = pos.totalAmount.toString();
                          }
                          setSheetState(() {});
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),

                  // Opsi Nominal Uang Tunai / Quick Cash (Jika metode = Tunai)
                  if (pos.isCashMethod(pos.paymentMethod)) ...[
                    const Text('Nominal Uang Diterima (Quick Cash):', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                    const SizedBox(height: 8),

                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () {
                              pos.setCashReceived(pos.totalAmount);
                              cashController.text = pos.totalAmount.toString();
                              setSheetState(() {});
                            },
                            child: const Text('Pas'),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () {
                              pos.setCashReceived(20000);
                              cashController.text = '20000';
                              setSheetState(() {});
                            },
                            child: const Text('20rb'),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () {
                              pos.setCashReceived(50000);
                              cashController.text = '50000';
                              setSheetState(() {});
                            },
                            child: const Text('50rb'),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () {
                              pos.setCashReceived(100000);
                              cashController.text = '100000';
                              setSheetState(() {});
                            },
                            child: const Text('100rb'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    TextField(
                      controller: cashController,
                      keyboardType: TextInputType.number,
                      onChanged: (val) {
                        final parsed = int.tryParse(val) ?? 0;
                        pos.setCashReceived(parsed);
                        setSheetState(() {});
                      },
                      decoration: const InputDecoration(
                        labelText: 'Nominal Uang Tunai (Rp)',
                        filled: true,
                        fillColor: Color(0xFFF1EFEB),
                        border: OutlineInputBorder(borderSide: BorderSide.none),
                      ),
                    ),
                    const SizedBox(height: 12),

                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: const Color(0xFFF1EFEB), borderRadius: BorderRadius.circular(12)),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Kembalian Uang:', style: TextStyle(fontWeight: FontWeight.bold)),
                          Text(
                            currencyFormatter.format(pos.changeAmount),
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF356A58)),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 20),

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF7A5540),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      onPressed: () async {
                        // Popup konfirmasi "Sudah lunas?" utk metode NON-TUNAI
                        // (kalau di-enable owner di Setup). Tunai skip (uang udah di tangan).
                        final isCash = pos.isCashMethod(pos.paymentMethod);
                        if (pos.popupConfirmPayment && !isCash) {
                          final confirmed = await _showPaymentConfirmDialog(ctx, pos.paymentMethod, pos.totalAmount);
                          if (confirmed != true) return; // batal
                        }
                        final itemsCopy = List<CartItem>.from(pos.cartItems);
                        final trx = await pos.checkout(pos.activeCashierDisplay);
                        if (!mounted) return;
                        if (trx == null) {
                          // Gagal (mis. bayar kurang / voucher tak valid) → tetap di sheet + kasih tahu.
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text(pos.checkoutError ?? 'Transaksi belum bisa diselesaikan.'),
                            backgroundColor: Colors.red.shade700,
                          ));
                          return;
                        }
                        // Tutup SEMUA sheet (keranjang + metode bayar) sampai balik ke
                        // layar kasir, baru buka struk. Biar 'Selesai' di struk langsung ke kasir.
                        navigator.popUntil((route) => route.isFirst);
                        navigator.push(
                          MaterialPageRoute(
                            builder: (_) => ReceiptScreen(transaction: trx, items: itemsCopy),
                          ),
                        );
                      },
                      child: const Text('Selesaikan Transaksi & Cetak Struk ›', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  /// Popup konfirmasi "Sudah lunas?" utk metode non-tunai (QRIS/Transfer/dst).
  /// Return true kalau 'Sudah', false/null kalau batal.
  Future<bool?> _showPaymentConfirmDialog(BuildContext ctx, String method, int total) async {
    return showDialog<bool>(
      context: ctx,
      barrierDismissible: false,
      builder: (dlgCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('✅ Konfirmasi Pembayaran', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.payment, size: 48, color: const Color(0xFF7A5540)),
            const SizedBox(height: 12),
            Text(
              'Metode: $method',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text('Total: Rp$total', style: const TextStyle(fontSize: 13, color: Colors.grey)),
            const SizedBox(height: 16),
            const Text(
              'Pastikan pembayaran sudah masuk/terverifikasi di aplikasi pembayaran sebelum melanjutkan.',
              style: TextStyle(fontSize: 12, color: Colors.black87),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            const Text('Sudah lunas?', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF356A58))),
          ],
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          OutlinedButton(
            style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.pop(dlgCtx, false),
            child: const Text('Belum'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF356A58), foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(dlgCtx, true),
            child: const Text('Sudah'),
          ),
        ],
      ),
    );
  }

  void _showPinDialog(BuildContext context, SettingsProvider settings) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('🔒 PIN / Password Admin'),
        content: TextField(
          controller: controller,
          obscureText: true,
          keyboardType: TextInputType.visiblePassword,
          decoration: const InputDecoration(hintText: 'Masukkan PIN / Password Admin'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
          ElevatedButton(
            onPressed: () {
              if (settings.verifyPin(controller.text)) {
                Navigator.pop(context);
                setState(() => _currentBottomNav = 3);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('❌ PIN Admin Salah!')));
              }
            },
            child: const Text('Masuk'),
          ),
        ],
      ),
    );
  }

  void _showHistoryDialog(BuildContext context, PosProvider pos, NumberFormat currencyFormatter) async {
    final now = DateTime.now();
    final bDate = now.hour < 6 ? now.subtract(const Duration(days: 1)) : now;
    final bDateKey = DateFormat('yyyy-MM-dd').format(bDate);

    final trxs = await DbHelper().getTodayTransactions(bDateKey);

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (dlgCtx) => AlertDialog(
        title: const Text('📜 Riwayat Transaksi Hari Ini'),
        content: SizedBox(
          width: double.maxFinite,
          child: trxs.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(20),
                  child: Text('Belum ada transaksi terproses hari ini.', textAlign: TextAlign.center),
                )
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: trxs.length,
                  itemBuilder: (ctx, i) {
                    final t = trxs[i];
                    final isVoid = t.status == 'VOID';
                    return Card(
                      color: isVoid ? Colors.red.shade50 : Colors.white,
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        title: Text(
                          t.code,
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, decoration: isVoid ? TextDecoration.lineThrough : null),
                        ),
                        subtitle: Text(
                          '${t.cashierName} • ${t.paymentMethod} • ${DateFormat('HH:mm').format(t.createdAt)}${isVoid ? " (VOID)" : ""}',
                          style: const TextStyle(fontSize: 11),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              currencyFormatter.format(t.totalAmount),
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: isVoid ? Colors.red : const Color(0xFF7A5540)),
                            ),
                            if (!isVoid) ...[
                              const SizedBox(width: 4),
                              IconButton(
                                icon: const Icon(Icons.block, color: Colors.red, size: 18),
                                tooltip: 'Void Transaksi',
                                onPressed: () => _confirmVoidTransaction(context, dlgCtx, pos, t),
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dlgCtx), child: const Text('Tutup')),
        ],
      ),
    );
  }

  void _confirmVoidTransaction(BuildContext parentCtx, BuildContext dlgCtx, PosProvider pos, TransactionModel trx) {
    final reasonCtrl = TextEditingController(text: 'Salah Input Kasir');
    showDialog(
      context: dlgCtx,
      builder: (confirmCtx) => AlertDialog(
        title: Text('🔴 Void Transaksi ${trx.code}?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Transaksi akan dibatalkan, stok bahan dikembalikan, dan nominal dikurangkan dari omzet.'),
            const SizedBox(height: 12),
            TextField(
              controller: reasonCtrl,
              decoration: const InputDecoration(labelText: 'Alasan Void', filled: true, fillColor: Color(0xFFF1EFEB)),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(confirmCtx), child: const Text('Batal')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () async {
              final reason = reasonCtrl.text.trim();
              if (reason.isNotEmpty) {
                await pos.voidTransaction(trx.id, reason);
                if (mounted) {
                  Navigator.pop(confirmCtx);
                  Navigator.pop(dlgCtx);
                  ScaffoldMessenger.of(parentCtx).showSnackBar(SnackBar(content: Text('✓ Transaksi ${trx.code} berhasil di-VOID!')));
                }
              }
            },
            child: const Text('Ya, Void Transaksi'),
          ),
        ],
      ),
    );
  }

  Widget _buildCashierSelectorBar(PosProvider pos) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: DbHelper().getEmployees(),
      builder: (context, snapshot) {
        final emps = snapshot.data ?? [
          {'name': 'Andi'},
          {'name': 'Budi'},
          {'name': 'Citra'},
        ];

        final currentActive = pos.activeCashier;
        final selectedValue = emps.any((e) => e['name'] == currentActive)
            ? currentActive
            : (emps.isNotEmpty ? emps.first['name'] as String : 'Andi');

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFFF5F3F0),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFD6C7BC)),
          ),
          child: Row(
            children: [
              const Icon(Icons.account_circle, size: 20, color: Color(0xFF7A5540)),
              const SizedBox(width: 8),
              const Text(
                'Kasir Shift Saat Ini:',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF51443B)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: selectedValue,
                    isDense: true,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF7A5540)),
                    icon: const Icon(Icons.arrow_drop_down, color: Color(0xFF7A5540)),
                    items: emps.map((e) {
                      final name = e['name'] as String;
                      return DropdownMenuItem<String>(
                        value: name,
                        child: Text(name),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) pos.setActiveCashier(val);
                    },
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showSelectCashierDialog(BuildContext context, PosProvider pos) async {
    final db = DbHelper();
    var emps = await db.getEmployees();
    if (emps.isEmpty) {
      await db.insertEmployee('Andi');
      await db.insertEmployee('Budi');
      await db.insertEmployee('Citra');
      emps = await db.getEmployees();
    }

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('👤 Pilih Kasir Aktif'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: emps.map((e) {
              final name = e['name'] as String;
              return RadioListTile<String>(
                activeColor: const Color(0xFF7A5540),
                title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
                value: name,
                groupValue: pos.activeCashier,
                onChanged: (val) {
                  if (val != null) {
                    pos.setActiveCashier(val);
                    Navigator.pop(ctx);
                  }
                },
              );
            }).toList(),
          ),
        );
      },
    );
  }
}
