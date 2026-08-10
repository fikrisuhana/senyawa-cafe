import subprocess
import os

sql = '''
select json_build_object(
 'exportedFrom','pos-cafe dev (172.16.1.5)',
 'bahan', (select coalesce(json_agg(row_to_json(x)),'[]') from (select name,unit,stock,"minStock" as min_stock from "Packaging" order by name) x),
 'menu', (select coalesce(json_agg(row_to_json(x)),'[]') from (select name,category,price,cost,active,"sortOrder" as urutan from "MenuItem" order by "sortOrder",name) x),
 'menuBahan', (select coalesce(json_agg(row_to_json(x)),'[]') from (select mi.name as menu, p.name as bahan, ms.qty from "MenuStock" ms join "MenuItem" mi on mi.id=ms."menuItemId" join "Packaging" p on p.id=ms."packagingId" order by mi.name) x),
 'varianGrup', (select coalesce(json_agg(row_to_json(x)),'[]') from (select mi.name as menu, vg.name as grup, vg.type as tipe, vg.required as wajib, vg."sortOrder" as urutan from "VariantGroup" vg join "MenuItem" mi on mi.id=vg."menuItemId" order by mi.name, vg."sortOrder") x),
 'varianOpsi', (select coalesce(json_agg(row_to_json(x)),'[]') from (select mi.name as menu, vg.name as grup, vo.name as opsi, vo."priceDelta" as tambahan, vo."sortOrder" as urutan from "VariantOption" vo join "VariantGroup" vg on vg.id=vo."groupId" join "MenuItem" mi on mi.id=vg."menuItemId" order by mi.name, vg."sortOrder", vo."sortOrder") x),
 'varianBahan', (select coalesce(json_agg(row_to_json(x)),'[]') from (select mi.name as menu, vg.name as grup, vo.name as opsi, p.name as bahan, vos.qty from "VariantOptionStock" vos join "VariantOption" vo on vo.id=vos."optionId" join "VariantGroup" vg on vg.id=vo."groupId" join "MenuItem" mi on mi.id=vg."menuItemId" join "Packaging" p on p.id=vos."packagingId") x),
 'voucher', (select coalesce(json_agg(row_to_json(x)),'[]') from (select name,type,value,active,"maxUses" as kuota,"validFrom" as berlaku_dari,"validUntil" as berlaku_sampai from "Voucher" order by name) x),
 'karyawan', (select coalesce(json_agg(row_to_json(x)),'[]') from (select name,active from "Employee" order by name) x),
 'pengaturan', (select coalesce(json_object_agg(key,value),'{}') from "Setting")
);
'''

os.makedirs('seed', exist_ok=True)
print("Executing query on 172.16.1.5...")
cmd = ["ssh", "-o", "StrictHostKeyChecking=no", "mint@172.16.1.5", "cat > /tmp/query.sql && docker exec -i pos-cafe-db-1 psql -U poscafe -d poscafe -tA < /tmp/query.sql && rm /tmp/query.sql"]

res = subprocess.run(cmd, input=sql, capture_output=True, text=True, encoding='utf-8', errors='replace')

print("Return code:", res.returncode)
if res.stderr:
    print("STDERR:", res.stderr)

output = (res.stdout or "").strip()
print("STDOUT length:", len(output))

if output:
    filepath = os.path.join('seed', 'seed.raw.json')
    with open(filepath, 'w', encoding='utf-8') as f:
        f.write(output)
    print(f"SUCCESS! File saved to {filepath} ({len(output)} bytes)")
