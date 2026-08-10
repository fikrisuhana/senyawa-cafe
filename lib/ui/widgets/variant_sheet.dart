import 'package:flutter/material.dart';
import '../../models/models.dart';
import '../../services/db_helper.dart';

class VariantSheet extends StatefulWidget {
  final MenuItemModel menuItem;
  final Function(List<String> selectedVariants, int extraPrice, String note) onAdd;

  const VariantSheet({
    super.key,
    required this.menuItem,
    required this.onAdd,
  });

  @override
  State<VariantSheet> createState() => _VariantSheetState();
}

class _VariantSheetState extends State<VariantSheet> {
  List<VariantGroupModel> _groups = [];
  Map<String, List<VariantOptionModel>> _optionsMap = {};
  final Map<String, String> _singleSelections = {};
  final Set<String> _multiSelections = {};
  final TextEditingController _noteController = TextEditingController();
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadVariants();
  }

  Future<void> _loadVariants() async {
    final db = DbHelper();
    var groups = await db.getVariantGroupsForMenu(widget.menuItem.name);
    Map<String, List<VariantOptionModel>> optionsMap = {};

    if (groups.isNotEmpty) {
      // Muat opsi ASLI dari DB untuk tiap grup yang dibuat admin.
      for (final g in groups) {
        final opts = await db.getVariantOptions(widget.menuItem.name, g.groupName);
        optionsMap[g.groupName] = opts;
        // Grup "Pilih 1" (SINGLE) yang wajib → auto-pilih opsi pertama.
        if (opts.isNotEmpty && g.type == 'SINGLE') {
          _singleSelections[g.groupName] = opts.first.optionName;
        }
      }
    } else if (widget.menuItem.category.toUpperCase() == 'KOPI' || widget.menuItem.category.toUpperCase() == 'NON-KOPI') {
      // Fallback: menu kopi belum diatur variannya → kasih pilihan Suhu default.
      groups = [
        VariantGroupModel(id: 999, menuName: widget.menuItem.name, groupName: 'Suhu', type: 'SINGLE', required: true, sortOrder: 0)
      ];
      optionsMap['Suhu'] = [
        VariantOptionModel(id: 9991, menuName: widget.menuItem.name, groupName: 'Suhu', optionName: 'Dingin (Es)', priceDelta: 0, sortOrder: 0),
        VariantOptionModel(id: 9992, menuName: widget.menuItem.name, groupName: 'Suhu', optionName: 'Panas', priceDelta: 0, sortOrder: 1),
      ];
      _singleSelections['Suhu'] = 'Dingin (Es)';
    }

    final validGroups = groups.where((g) => (optionsMap[g.groupName] ?? []).isNotEmpty).toList();

    setState(() {
      _groups = validGroups;
      _optionsMap = optionsMap;
      _isLoading = false;
    });
  }

  String _formatGroupTitle(VariantGroupModel group) {
    // Tampilkan nama grup apa adanya (sesuai yang admin ketik) + badge Wajib.
    return '${group.groupName.trim()}${group.required ? " • Wajib" : ""}';
  }

  String _formatOptionLabel(VariantOptionModel opt) {
    // Nama opsi apa adanya; hanya legacy HOT/ICE (seed) yang di-Indonesiakan.
    String name = opt.optionName.trim();
    final upper = name.toUpperCase();
    if (upper == 'HOT') {
      name = 'Panas';
    } else if (upper == 'ICE') {
      name = 'Dingin (Es)';
    }
    if (opt.priceDelta > 0) {
      return '$name +Rp${opt.priceDelta}';
    }
    return name;
  }

  int get calculateExtraPrice {
    int extra = 0;
    _singleSelections.forEach((group, optionName) {
      final opts = _optionsMap[group] ?? [];
      final match = opts.firstWhere((o) => o.optionName == optionName, orElse: () => opts.first);
      extra += match.priceDelta;
    });
    for (var optionName in _multiSelections) {
      _optionsMap.forEach((_, opts) {
        for (var o in opts) {
          if (o.optionName == optionName) {
            extra += o.priceDelta;
          }
        }
      });
    }
    return extra;
  }

  @override
  Widget build(BuildContext context) {
    final totalItemPrice = widget.menuItem.price + calculateExtraPrice;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        color: Color(0xFFFFFFFF),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade400,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  widget.menuItem.name,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),

                // Variant Groups
                ..._groups.map((group) {
                  final opts = _optionsMap[group.groupName] ?? [];
                  final isMulti = group.type == 'MULTI';

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _formatGroupTitle(group),
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey.shade700),
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 8,
                          children: opts.map((opt) {
                            final bool isSelected = isMulti
                                ? _multiSelections.contains(opt.optionName)
                                : (_singleSelections[group.groupName] == opt.optionName);

                            final label = _formatOptionLabel(opt);

                            return FilterChip(
                              label: Text(label),
                              selected: isSelected,
                              onSelected: (selected) {
                                setState(() {
                                  if (isMulti) {
                                    if (selected) {
                                      _multiSelections.add(opt.optionName);
                                    } else {
                                      _multiSelections.remove(opt.optionName);
                                    }
                                  } else {
                                    _singleSelections[group.groupName] = opt.optionName;
                                  }
                                });
                              },
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  );
                }),

                // Catatan
                TextField(
                  controller: _noteController,
                  decoration: InputDecoration(
                    labelText: 'Catatan (misal: less sugar)',
                    filled: true,
                    fillColor: const Color(0xFFF1EFEB),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 16),

                // Submit Button
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Batal'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1A73E8),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        ),
                        onPressed: () {
                          List<String> selected = List<String>.from(_singleSelections.values);
                          selected.addAll(_multiSelections);

                          widget.onAdd(selected, calculateExtraPrice, _noteController.text);
                          Navigator.pop(context);
                        },
                        child: Text('Tambah • Rp$totalItemPrice'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}
