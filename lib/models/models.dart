/// Model Bahan & Kemasan (Packaging)
class PackagingModel {
  final int? id;
  final String name;
  final String unit;
  final int stock;
  final int minStock;

  PackagingModel({
    this.id,
    required this.name,
    required this.unit,
    required this.stock,
    required this.minStock,
  });

  factory PackagingModel.fromMap(Map<String, dynamic> map) {
    return PackagingModel(
      id: map['id'],
      name: map['name'] ?? '',
      unit: map['unit'] ?? 'pcs',
      stock: map['stock'] ?? 0,
      minStock: map['min_stock'] ?? map['minStock'] ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'unit': unit,
      'stock': stock,
      'min_stock': minStock,
    };
  }
}

/// Model Menu Item
class MenuItemModel {
  final int? id;
  final String name;
  final String category;
  final int price;
  final int cost;
  final bool active;
  final int sortOrder;

  MenuItemModel({
    this.id,
    required this.name,
    required this.category,
    required this.price,
    required this.cost,
    required this.active,
    required this.sortOrder,
  });

  factory MenuItemModel.fromMap(Map<String, dynamic> map) {
    return MenuItemModel(
      id: map['id'],
      name: map['name'] ?? '',
      category: map['category'] ?? 'KOPI',
      price: map['price'] ?? 0,
      cost: map['cost'] ?? 0,
      active: (map['active'] == 1 || map['active'] == true),
      sortOrder: map['urutan'] ?? map['sortOrder'] ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'category': category,
      'price': price,
      'cost': cost,
      'active': active ? 1 : 0,
      'sortOrder': sortOrder,
    };
  }
}

/// Model Grup Varian (Suhu, Shot, Topping)
class VariantGroupModel {
  final int? id;
  final String menuName;
  final String groupName;
  final String type; // SINGLE | MULTI
  final bool required;
  final int sortOrder;

  VariantGroupModel({
    this.id,
    required this.menuName,
    required this.groupName,
    required this.type,
    required this.required,
    required this.sortOrder,
  });

  factory VariantGroupModel.fromMap(Map<String, dynamic> map) {
    return VariantGroupModel(
      id: map['id'],
      // Baca kolom DB (snake_case) dulu, fallback ke key seed JSON.
      menuName: map['menu_name'] ?? map['menu'] ?? '',
      groupName: map['group_name'] ?? map['grup'] ?? map['name'] ?? '',
      type: map['type'] ?? map['tipe'] ?? 'SINGLE',
      required: (map['required'] == 1 || map['required'] == true || map['wajib'] == 1 || map['wajib'] == true),
      sortOrder: map['sort_order'] ?? map['urutan'] ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'menu_name': menuName,
      'group_name': groupName,
      'type': type,
      'required': required ? 1 : 0,
      'sort_order': sortOrder,
    };
  }
}

/// Model Opsi Varian (Panas, Dingin, Single, Double)
class VariantOptionModel {
  final int? id;
  final String menuName;
  final String groupName;
  final String optionName;
  final int priceDelta;
  final int sortOrder;

  VariantOptionModel({
    this.id,
    required this.menuName,
    required this.groupName,
    required this.optionName,
    required this.priceDelta,
    required this.sortOrder,
  });

  factory VariantOptionModel.fromMap(Map<String, dynamic> map) {
    return VariantOptionModel(
      id: map['id'],
      // Baca kolom DB (snake_case) dulu, fallback ke key seed JSON.
      menuName: map['menu_name'] ?? map['menu'] ?? '',
      groupName: map['group_name'] ?? map['grup'] ?? '',
      optionName: map['option_name'] ?? map['opsi'] ?? map['name'] ?? '',
      priceDelta: map['price_delta'] ?? map['tambahan'] ?? map['priceDelta'] ?? 0,
      sortOrder: map['sort_order'] ?? map['urutan'] ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'menu_name': menuName,
      'group_name': groupName,
      'option_name': optionName,
      'price_delta': priceDelta,
      'sort_order': sortOrder,
    };
  }
}

/// Model Voucher Diskon
class VoucherModel {
  final int? id;
  final String name;
  final String type; // PERCENT | NOMINAL
  final int value;
  final bool active;
  final int? kuota; // null = tak terbatas
  final int usedCount;
  final String? validFrom; // "YYYY-MM-DD" atau null
  final String? validUntil;

  VoucherModel({
    this.id,
    required this.name,
    required this.type,
    required this.value,
    required this.active,
    this.kuota,
    this.usedCount = 0,
    this.validFrom,
    this.validUntil,
  });

  factory VoucherModel.fromMap(Map<String, dynamic> map) {
    return VoucherModel(
      id: map['id'],
      name: map['name'] ?? '',
      type: map['type'] ?? 'PERCENT',
      value: map['value'] ?? 0,
      active: (map['active'] == 1 || map['active'] == true),
      kuota: map['kuota'],
      usedCount: map['used_count'] ?? 0,
      validFrom: (map['valid_from'] as String?)?.isEmpty == true ? null : map['valid_from'],
      validUntil: (map['valid_until'] as String?)?.isEmpty == true ? null : map['valid_until'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'type': type,
      'value': value,
      'active': active ? 1 : 0,
      'kuota': kuota,
      'used_count': usedCount,
      'valid_from': validFrom,
      'valid_until': validUntil,
    };
  }

  /// Alasan voucher tak bisa dipakai sekarang (null = boleh).
  String? invalidReason(DateTime now) {
    if (!active) return 'Voucher nonaktif';
    if (validFrom != null && validFrom!.isNotEmpty) {
      final f = DateTime.tryParse('${validFrom!}T00:00:00');
      if (f != null && now.isBefore(f)) return 'Voucher belum berlaku';
    }
    if (validUntil != null && validUntil!.isNotEmpty) {
      final u = DateTime.tryParse('${validUntil!}T23:59:59');
      if (u != null && now.isAfter(u)) return 'Voucher kadaluarsa';
    }
    if (kuota != null && usedCount >= kuota!) return 'Kuota voucher habis';
    return null;
  }
}

/// Model Item Keranjang (Cart Item)
class CartItem {
  final MenuItemModel menu;
  int quantity;
  final List<String> selectedVariants; // ["Dingin", "Double (+3k)", "Regal (+3k)"]
  final int variantExtraPrice;
  final String note;

  CartItem({
    required this.menu,
    this.quantity = 1,
    required this.selectedVariants,
    this.variantExtraPrice = 0,
    this.note = '',
  });

  int get unitPrice => menu.price + variantExtraPrice;
  int get totalPrice => unitPrice * quantity;

  String get variantDescription => selectedVariants.join(', ');
}

/// Model Transaksi Penjualan
class TransactionModel {
  final String id;
  final String code;
  final DateTime createdAt;
  final String businessDate; // hari usaha "YYYY-MM-DD"
  final String cashierName;
  final String orderType; // DINE_IN | TAKEAWAY
  final String paymentMethod; // CASH | QRIS | TRANSFER
  final int subtotal;
  final int discountAmount;
  final String? voucherName;
  final int totalAmount;
  final int cashReceived;
  final int changeAmount;
  final int costTotal; // total modal/HPP semua item (buat hitung untung)
  final String status; // ACTIVE | VOID
  final bool synced;

  TransactionModel({
    required this.id,
    required this.code,
    required this.createdAt,
    required this.businessDate,
    required this.cashierName,
    required this.orderType,
    required this.paymentMethod,
    required this.subtotal,
    required this.discountAmount,
    this.voucherName,
    required this.totalAmount,
    required this.cashReceived,
    required this.changeAmount,
    this.costTotal = 0,
    this.status = 'ACTIVE',
    this.synced = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'code': code,
      'created_at': createdAt.toIso8601String(),
      'business_date': businessDate,
      'cashier_name': cashierName,
      'order_type': orderType,
      'payment_method': paymentMethod,
      'subtotal': subtotal,
      'discount_amount': discountAmount,
      'voucher_name': voucherName,
      'total_amount': totalAmount,
      'cash_received': cashReceived,
      'change_amount': changeAmount,
      'cost_total': costTotal,
      'status': status,
      'synced': synced ? 1 : 0,
    };
  }

  factory TransactionModel.fromMap(Map<String, dynamic> map) {
    return TransactionModel(
      id: (map['id'] ?? '').toString(),
      code: (map['code'] ?? '').toString(),
      createdAt: map['created_at'] != null ? (DateTime.tryParse(map['created_at'].toString()) ?? DateTime.now()) : DateTime.now(),
      businessDate: (map['business_date'] ?? '').toString(),
      cashierName: (map['cashier_name'] ?? 'Kasir').toString(),
      orderType: (map['order_type'] ?? 'DINE_IN').toString(),
      paymentMethod: (map['payment_method'] ?? 'CASH').toString(),
      subtotal: (map['subtotal'] as num?)?.toInt() ?? 0,
      discountAmount: (map['discount_amount'] as num?)?.toInt() ?? 0,
      voucherName: map['voucher_name']?.toString(),
      totalAmount: (map['total_amount'] as num?)?.toInt() ?? 0,
      cashReceived: (map['cash_received'] as num?)?.toInt() ?? 0,
      changeAmount: (map['change_amount'] as num?)?.toInt() ?? 0,
      costTotal: (map['cost_total'] as num?)?.toInt() ?? 0,
      status: (map['status'] ?? 'ACTIVE').toString(),
      synced: map['synced'] == 1 || map['synced'] == true,
    );
  }
}

/// Model Pengaturan Toko (Store Settings)
class StoreSettingModel {
  final String storeName;
  final String receiptHeader;
  final String receiptFooter;
  final String quickCash;
  final String paperWidth;
  final String shifts;
  final int kasAwal;

  StoreSettingModel({
    required this.storeName,
    required this.receiptHeader,
    required this.receiptFooter,
    required this.quickCash,
    required this.paperWidth,
    required this.shifts,
    required this.kasAwal,
  });

  factory StoreSettingModel.fromMap(Map<String, dynamic> map) {
    return StoreSettingModel(
      storeName: map['storeName'] ?? 'Ruang Senyawa',
      receiptHeader: map['receiptHeader'] ?? 'Instagram: @r_senyawa',
      receiptFooter: map['receiptFooter'] ?? 'Terima kasih sudah berkunjung.',
      quickCash: map['quickCash'] ?? 'pas,20000,50000,100000',
      paperWidth: map['paperWidth'] ?? '58',
      shifts: map['shifts'] ?? 'Sore,Malam',
      kasAwal: int.tryParse(map['kasAwal']?.toString() ?? '250000') ?? 250000,
    );
  }
}
