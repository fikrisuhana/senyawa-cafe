#!/usr/bin/env bash
set -e

mkdir -p seed

SQL_QUERY='select json_build_object(
 "exportedFrom","pos-cafe dev (172.16.1.5)",
 "bahan", (select coalesce(json_agg(row_to_json(x)),"[]") from (select name,unit,stock,"minStock" as min_stock from "Packaging" order by name) x),
 "menu", (select coalesce(json_agg(row_to_json(x)),"[]") from (select name,category,price,cost,active,"sortOrder" as urutan from "MenuItem" order by "sortOrder",name) x),
 "menuBahan", (select coalesce(json_agg(row_to_json(x)),"[]") from (select mi.name as menu, p.name as bahan, ms.qty from "MenuStock" ms join "MenuItem" mi on mi.id=ms."menuItemId" join "Packaging" p on p.id=ms."packagingId" order by mi.name) x),
 "varianGrup", (select coalesce(json_agg(row_to_json(x)),"[]") from (select mi.name as menu, vg.name as grup, vg.type as tipe, vg.required as wajib, vg."sortOrder" as urutan from "VariantGroup" vg join "MenuItem" mi on mi.id=vg."menuItemId" order by mi.name, vg."sortOrder") x),
 "varianOpsi", (select coalesce(json_agg(row_to_json(x)),"[]") from (select mi.name as menu, vg.name as grup, vo.name as opsi, vo."priceDelta" as tambahan, vo."sortOrder" as urutan from "VariantOption" vo join "VariantGroup" vg on vg.id=vo."groupId" join "MenuItem" mi on mi.id=vg."menuItemId" order by mi.name, vg."sortOrder", vo."sortOrder") x),
 "varianBahan", (select coalesce(json_agg(row_to_json(x)),"[]") from (select mi.name as menu, vg.name as grup, vo.name as opsi, p.name as bahan, vos.qty from "VariantOptionStock" vos join "VariantOption" vo on vo.id=vos."optionId" join "VariantGroup" vg on vg.id=vo."groupId" join "MenuItem" mi on mi.id=vg."menuItemId" join "Packaging" p on p.id=vos."packagingId") x),
 "voucher", (select coalesce(json_agg(row_to_json(x)),"[]") from (select name,type,value,active,"maxUses" as kuota,"validFrom" as berlaku_dari,"validUntil" as berlaku_sampai from "Voucher" order by name) x),
 "karyawan", (select coalesce(json_agg(row_to_json(x)),"[]") from (select name,active from "Employee" order by name) x),
 "pengaturan", (select coalesce(json_object_agg(key,value),"{}") from "Setting")
);'

ssh -n -o StrictHostKeyChecking=no mint@172.16.1.5 "docker exec pos-cafe-db-1 psql -U poscafe -d poscafe -tA -c '$SQL_QUERY'" > seed/seed.raw.json

echo "raw bytes: $(wc -c < seed/seed.raw.json)"
