# ビルド手順（詳細）

MIU Darwin 向けの Ptyxis は **Fedora からのクロスコンパイル**です。
OpenBSD 版のように対象機で組むのではなく、対象機は 256 MB の
ディスクイメージで、そこへ書き込んでから QEMU で起こします。

## 前提

この port だけでは組めません。MIU Darwin の作業ツリーと、そこで組み終えた
依存が要ります。

| 要るもの | 置き場（MIU Darwin ツリー内） |
|----------|------------------------------|
| meson クロスファイル | `userland/ptyxis/miu-config/miu-cross.ini` |
| C ライブラリ | `userland/libsystem/libSystem.B.dylib` |
| C++ ライブラリ | `userland/libcxx/libc++.1.dylib` |
| GTK4 | `userland/gtk4/stage/` |
| libadwaita | `userland/libadwaita/stage/` |
| VTE | `userland/vte/stage/` |
| JSON-GLib | `userland/json-glib/stage/` |
| lz4 | `userland/lz4/stage/` |

`libc++.1.dylib` は 2026-09-01 に新設したものです。C++ の
`operator new` / `delete` は「利用者が差し替えてよい記号」と決まっており、
Mach-O のリンカはこれを **weak import** として書き出します。weak import は
「実行時に読み込まれた物のどれかから引く」意味なので、リンカは静的な書庫
(`libc++.a`) から `new.o` を引き込みません。C++ の共有ライブラリが無いと、
VTE は `operator new` を誰も持たないまま出来上がり、実機で

```
fixups: 引けない名 __Znwm
dyld: fixups を当てられない: /usr/lib/libvte-2.91-gtk4.0.dylib
```

で止まります。

## 手順

### 1. 取得と検証

```sh
curl -O https://download.gnome.org/sources/ptyxis/50/ptyxis-50.1.tar.xz
sha256sum -c miudarwin-port/distinfo
tar xf ptyxis-50.1.tar.xz
cd ptyxis-50.1
```

`distinfo` は **hex** です。OpenBSD の `distinfo` は base64 ですが、MIU Darwin
の道具は `sha256sum -c` で確かめるので、そちらに合わせています。手元の道具で
確かめられない記録は、無いのと大差ありません。

### 2. パッチ

```sh
patch -p0 < ../miudarwin-port/patches/patch-agent_meson_build
patch -p0 < ../miudarwin-port/patches/patch-src_ptyxis-tab_c
```

`-p0` です（OpenBSD の port 形式に合わせて `--- src/foo.c.orig` の形で
書いてあります）。上流へ送る `upstream-patches/` の方は `-p1` の
`a/` `b/` 形式です。

### 3. ビルド

```sh
meson setup build \
  --cross-file "$MIU_TREE/userland/ptyxis/miu-config/miu-cross.ini" \
  --prefix=/usr --libdir=lib
ninja -C build
```

`meson setup --reconfigure` ではクロスファイルの `[built-in options]` が
読み直されません。クロスファイルを変えたら `--wipe` するか、build ディレクトリを
消して組み直してください（2026-09-01 に実測）。

### 4. stage への収め

```sh
DESTDIR=$PWD/stage meson install -C build --no-rebuild
```

### 5. イメージへ配る

MIU Darwin ツリー側で:

```sh
scripts/deploy-ptyxis.sh
```

配るもの:

- `/usr/bin/ptyxis`
- `/usr/libexec/ptyxis-agent`（`LIBEXECDIR` として焼き込まれているので、
  別の場所に置くと agent を起こせません）
- `/usr/lib/libvte-2.91-gtk4.0.dylib`
- `/usr/lib/liblz4.1.dylib`
- `/usr/lib/libc++.1.dylib`
- desktop ファイル、アイコン 2 枚、日本語の翻訳

さらに GSettings のスキーマを編み直します。Ptyxis は起動時に自分のスキーマを
引き、無いと GLib は **g_error で落とします**（警告ではありません）。しかも
読むのは `.gschema.xml` ではなく `gschemas.compiled` 一枚なので、置くだけでは
足りません。

配る前に、Ptyxis が引く dylib がすべてイメージに在るかを `otool` で数えます。
一本でも欠けると dyld は黙って止まり、窓が開かないだけで理由が出ません。

### 6. 実機で起こす

```sh
MIU_SHOT_APP=/usr/bin/ptyxis ./scripts/shot-gtk4.sh
```

QEMU/TCG は非常に遅く、agent との接続まで 80 秒ほどかかります。

## よくある詰まり

### `undefined symbol: _vte_regex_*` の山が出る

`libvte-2.91-gtk4.dylib`（版なしの名前）が stage に無いと、`-lvte-2.91-gtk4`
が解決できません。このとき ld64.lld は **「library not found」とは言わず**、
黙って飛ばして後から記号が無いと言います。エラーの見た目が原因を指さないので
注意してください。

### `wordexp.h` が無い

MIU Darwin の C ライブラリに `wordexp(3)` を実装済みです。sysroot が古い場合は
`userland/libmiu/build.sh` を走らせ直してください。

### 実機で `Failed to spawn ptyxis-agent: errno 43`

`errno 43` は Darwin の `EPROTONOSUPPORT` です。`socketpair()` に
`SOCK_CLOEXEC | SOCK_NONBLOCK` を重ねて渡したとき、その上位ビットが核まで
届いていると出ます。libmiu 側で剥がす必要があり、2026-09-01 に直しました。
`scripts/check-fdflag.sh` がこれを実機で測ります。
