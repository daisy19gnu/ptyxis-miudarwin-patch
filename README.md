# Ptyxis for MIU Darwin

MIU Darwin 向けの [Ptyxis](https://gitlab.gnome.org/chergert/ptyxis) port です。
Ptyxis は GTK4/libadwaita ベースの GNOME ターミナルエミュレータです。

MIU Darwin は Darwin/XNU をベースとしたディストリビューションで、独自の C
ライブラリ (libmiu、`/usr/lib/libSystem.B.dylib` として配布) と独自の Wayland
コンポジタを持ちます。ビルドは Fedora からのクロスコンパイルです。

姉妹 port: [ptyxis-openbsd-patch](https://github.com/daisy19gnu/ptyxis-openbsd-patch)

## 現在のバージョン

| 項目 | バージョン |
|------|-----------|
| Ptyxis | **50.1** |
| MIU Darwin | 0.0.1 (Darwin 24.0.0) |
| パッチリビジョン | r1 |
| ビルド確認日 | 2026-09-01 |

## 動作確認済み依存ライブラリ

| パッケージ | バージョン | 状態 |
|-----------|-----------|------|
| GTK4 | 4.20.4 | OK |
| libadwaita | 1.8.7 | OK |
| VTE (GTK4) | 0.80.5 | OK |
| JSON-GLib | 1.10.8 | OK |
| GLib | 2.86.0 | OK |
| Pango | 1.57.0 | OK |
| cairo | 1.18.4 | OK |

いずれも MIU Darwin 向けにクロスビルドしたものです。

## リポジトリ構成

```
MIU-Darwin-Ptyxis/
├── miudarwin-port/            # MIU Darwin port ファイル群
│   ├── distinfo              # チェックサム (SHA256、hex)
│   ├── README.MIUDarwin      # MIU Darwin 固有のビルド手順
│   ├── patches/              # MIU Darwin 用パッチ (2種)
│   │   ├── patch-agent_meson_build      # 非 Linux で glibc を強制リンクしない
│   │   ├── patch-src_ptyxis-tab_c       # sys/wait.h インクルード追加
│   │   └── ptyxis-50.1-r1/              # 現行リビジョン保存
│   └── pkg/                  # パッケージメタデータ
│       ├── DESCR             # パッケージ説明文
│       └── PLIST             # インストールファイルリスト
├── upstream-patches/          # 上流へのバグ報告用パッチ
│   ├── 0001-agent-do-not-force-link-glibc-on-non-linux.patch
│   ├── 0002-tab-include-sys-wait-h-for-wait-macros.patch
│   └── HOWTO_SUBMIT.md       # 上流へのパッチ提出手順
├── build-ptyxis.sh            # クロスビルドスクリプト
├── check-version.sh           # バージョン確認スクリプト
├── BUILD_INSTRUCTIONS.md      # 詳細なビルド手順
└── SUMMARY.md                 # 作業サマリー
```

OpenBSD 版に在る `Makefile` と ports ツリー関連のファイルはありません。
MIU Darwin には ports が無く、同じ役割を `build.sh` (組む) と
`deploy-ptyxis.sh` (イメージへ配る) が担います。対応表は
[miudarwin-port/README.MIUDarwin](miudarwin-port/README.MIUDarwin) にあります。

## ビルド方法

### 前提

MIU Darwin の作業ツリー (別リポジトリ) と、そこで組み終えた GTK4 /
libadwaita / VTE などが必要です。この port だけでは組めません。

### 手動 meson ビルド

```sh
curl -O https://download.gnome.org/sources/ptyxis/50/ptyxis-50.1.tar.xz
sha256sum -c miudarwin-port/distinfo   # hex 形式
tar xf ptyxis-50.1.tar.xz
cd ptyxis-50.1

# パッチ適用（2種、アルファベット順）
patch -p0 < ../miudarwin-port/patches/patch-agent_meson_build
patch -p0 < ../miudarwin-port/patches/patch-src_ptyxis-tab_c

# ビルド（クロスファイルは MIU Darwin ツリーの miu-config/miu-cross.ini）
meson setup build --cross-file /path/to/miu-cross.ini --prefix=/usr --libdir=lib
ninja -C build
```

### イメージへの配置

MIU Darwin は 256 MB のディスクイメージから起動するため、インストールは
イメージへの書き込みになります。

```sh
scripts/deploy-ptyxis.sh    # MIU Darwin ツリー側
```

Ptyxis が引く dylib がイメージに揃っているかを otool で数えてから書き込みます。
一本でも欠けると dyld は黙って止まる（窓が開かないだけで理由が出ない）ため、
書き込む前に捕まえます。実際この確認で liblz4 の配り漏れを検出しました。

## MIU Darwin 向けパッチの概要 (2種)

### patch-agent_meson_build

`agent/meson.build` は CPU が x86_64 でありさえすれば
`x86_64/force_link_glibc_2.17.h` を取り込みます。この見出しは glibc の
シンボルバージョンを固定するもので、MIU Darwin には glibc が無いため
agent のコンパイルが通りません。

条件は `target_machine` ではなく **`host_machine`** に対して書いています。
meson の `target_machine` は「組んでいる物自体がコンパイラであるとき」だけ
意味を持ち、ふつうのアプリケーションでは「コードが動く機械」は
`host_machine` です。ネイティブビルドでは両者は同じなので違いは出ませんが、
MIU Darwin はクロスコンパイルなので実際に食い違います。

OpenBSD 版も同じ箇所を修正しています（あちらは `target_machine`。
ネイティブビルドなので等価）。

### patch-src_ptyxis-tab_c

`src/ptyxis-tab.c` が `WIFEXITED` / `WEXITSTATUS` / `WIFSIGNALED` /
`WTERMSIG` を使いながら `<sys/wait.h>` を取り込んでいません。POSIX では
これらはその見出しに在り、glibc では別の見出しが間接的に引いてくるため
たまたま通っています。

OpenBSD 版も同じ箇所を修正しています。**二つの port が独立に同じ欠落を
踏んでいる**ので、上流に無いのが素直な見立てです。よって
`upstream-patches/` にも置いています。

## 当てなくて済んだパッチ

### wordexp(3)

OpenBSD 版は `ptyxis_path_expand()` の `wordexp()` を無効化しています
（OpenBSD が持たないため）。MIU Darwin は **自前の C ライブラリに
`wordexp(3)` を実装した**ので、この修正は要りません。

その実装は、扱えないもの（経路名の展開、コマンド置換）を黙って素通しせず
**誤りとして返します**。素通しにすると呼んだ側は展開済みだと思って違う経路を
掴むためで、Ptyxis 自身も「失敗したら入力の複製を返す」と書いています
(`ptyxis-util.c:180-181`)。glibc と 36 件の入力で突き合わせ済みです。

### pledge(2) / unveil(2)

OpenBSD 固有のサンドボックス。MIU Darwin に相当する仕組みはまだありません。

## パッチバージョニング

OpenBSD 版と同じ規則です。

- 命名規則: `ptyxis-{VERSION}-r{N}`（例: `ptyxis-50.1-r1`）
- 各リビジョンはディレクトリ保存（tar.gz は .gitignore で除外）
- パッチは `diff -u` で生成
- `patches/patch-*` は常に最新リビジョンのコピーを配置

## 動作確認状況

- [x] ビルド成功（Fedora からのクロスコンパイル、警告のみ・エラー 0）
- [x] 全2パッチ適用成功（上流 tarball に対して実測）
- [x] 成果物が Mach-O / chained fixups / NOUNDEFS であることを確認
- [x] 参照する dylib がすべて `/usr/lib/` を指す（`@rpath` が残らない）
- [x] イメージへの配置成功（依存 33 本すべて在庫確認）
- [x] 実機で起動し、`ptyxis-agent` の spawn と接続まで到達
- [ ] **窓の表示（未達）**

### 窓が出るまでの到達点

実機 (QEMU/TCG) での記録は以下まで進みます。

```
Set RLIMIT_NOFILE
GLib-GIO: gio-vfs / gsettings-backend の既定を解決
Adwaita: Settings portal not found (D-Bus 無し。警告)
ptyxis-agent: 起動
Ptyxis: Container session:session added at position 0
Ptyxis: Connected to ptyxis-agent          <- agent との接続まで成功
Ptyxis: Custom links have changed
Gtk-WARNING: Unable to acquire session bus (D-Bus 無し。警告)
PCRE2 library was built without JIT support <- VTE の regex 初期化
```

ここから先へ進まず、620 秒待っても変化がありません（時間の問題ではない）。
`--standalone` を渡しても同じです。

D-Bus の不在が原因かどうかは **まだ確かめていません**。同じ D-Bus 警告を
出しながら窓を出せている GTK4 アプリ（MIU Darwin の greeter）が在るため、
GApplication が D-Bus 無しで動くこと自体は確認済みです。切り分けは継続中です。

## 上流へ送る予定のパッチ

`upstream-patches/` の 2 枚は、いずれも MIU Darwin 固有ではなく
**非 Linux 全般で踏む**問題です。OpenBSD 版が同じ箇所を独立に修正している
ことがその裏付けになります。提出手順は
[upstream-patches/HOWTO_SUBMIT.md](upstream-patches/HOWTO_SUBMIT.md)。

## 利用できない機能（Linux 専用）

| 機能 | 理由 |
|------|------|
| Podman/Toolbox/Distrobox 統合 | Linux コンテナランタイム依存 |
| libportal 機能 | Flatpak ポータル依存 |
| systemd スコープ | systemd 依存 |
| GPU レンダリング | cairo レンダラのみ。GL はまだ無い |

## 参考リンク

- [Ptyxis 上流リポジトリ](https://gitlab.gnome.org/chergert/ptyxis)
- [Ptyxis リリースタグ](https://gitlab.gnome.org/chergert/ptyxis/-/tags)
- [ptyxis-openbsd-patch](https://github.com/daisy19gnu/ptyxis-openbsd-patch) — 姉妹 port
