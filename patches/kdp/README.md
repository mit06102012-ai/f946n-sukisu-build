# KDP / RKP / DEFEX patches

Đặt file `.patch` vào thư mục này.

Workflow sẽ apply bằng:

```bash
patch -p1 < patches/kdp/<file>.patch
```

Patch phải khớp source Samsung `F946NKSS5DYBD`.

Không có patch đúng:
- Kernel có thể build thành công
- Nhưng bootloop hoặc SukiSU bị chặn

Không đặt patch của F946B Android 13/15 vào đây nếu không kiểm tra.
