# F946N SukiSU cloud build

Workflow GitHub Actions để build kernel SukiSU cho **SM-F946N / F946NKSS5DYBD**.

## Cần chuẩn bị trước

Upload 6 file lên GitHub Release (hoặc chỗ có URL trực tiếp):

1. `SM-F946B_14_Opensource.zip` — base source
2. `SM-F946N_KOR_14_Opensource_dts.zip` — DTS F946N
3. `SM-F946B_14_Opensource_...F946NKSS5DYBD...zip` — patch
4. `toolchain.tar.gz` — toolchain Samsung đầy đủ (prebuilts)
5. `F946N_boot_stock.img` — boot stock
6. `F946N_init_boot_stock.img` — init_boot stock

## KDP/RKP/DEFEX

Đặt patch vào:

```
patches/kdp/*.patch
```

Workflow sẽ chạy:

```
patch -p1 < patches/kdp/*.patch
```

**Không có patch này thì kernel có thể bootloop dù build thành công.** Không có patch vạn năng cho mọi bản Samsung.

## AVB

Workflow tạo:

```
F946N_sukisu_vbmeta_disabled.img
```

Đây là vbmeta **flags=2** để tắt verify, không phải chữ ký Samsung. Không có private key Samsung thì không thể ký bằng key gốc.

## Chạy

1. Tạo repo GitHub
2. Push thư mục này
3. Actions → **Build F946N SukiSU kernel** → Run workflow
4. Nhập 6 URL + target `q5q_kor_singlex` + LTO `thin`
5. Tải artifact `f946n-sukisu`

## Flash

```
AP = F946N_sukisu_boot.tar
BL/CP/CSC = stock
```

Nếu bootloop:

- Flash `F946N_sukisu_vbmeta_disabled.img` vào AP/userdata (nếu cần)
- Hoặc về full stock

## Giới hạn

- Chưa test trên máy thật
- SukiSU trên Samsung non-GKI vẫn có thể bị KDP/RKP/DEFEX chặn
- Cần patch KDP đúng build
- Boot unsigned; Samsung có thể từ chối
- Tốt nhất dùng acc phụ và giữ full stock

## License

Chỉ dùng cho máy của bạn. Source Samsung theo giấy phép Samsung/GPL.
