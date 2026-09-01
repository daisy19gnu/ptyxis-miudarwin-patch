# Ptyxis for MIU Darwin - プロジェクト状況

## 現在の状態

| 項目 | 内容 |
|------|------|
| Ptyxis | 50.1 |
| MIU Darwin | 0.0.1 (Darwin 24.0.0, x86_64) |
| パッチリビジョン | r1 |
| ビルド | ✅ 成功（Fedora からのクロスコンパイル） |
| イメージへの配置 | ✅ 成功 |
| 実機での起動 | ⚠️ 途中まで（窓は未表示） |
| 最終更新 | 2026-09-01 |

## 適用中のパッチ (2つ)

| パッチ | 内容 |
|--------|------|
| `patch-agent_meson_build` | 非 Linux x86_64 で glibc を強制リンクしない |
| `patch-src_ptyxis-tab_c` | `<sys/wait.h>` を取り込む |

いずれも MIU Darwin 固有ではなく、**非 Linux 全般で踏む**問題です。
OpenBSD 版が同じ 2 箇所を独立に修正しており、それが裏付けになります。

### MIU Darwin 側で解決した問題（Ptyxis へのパッチ不要）

Ptyxis を通すために MIU Darwin の C ライブラリと動的リンカに入れた直しです。
Ptyxis 側には手を入れていません。

| 症状 | 原因 | 直した場所 |
|------|------|-----------|
| `wordexp.h` が無い | libc に `wordexp(3)` が無かった | libmiu に実装（glibc と 36 件で突き合わせ） |
| `undefined symbol: _vte_regex_*` | `libvte-2.91-gtk4.dylib` の版なし symlink が無く、`-lvte-2.91-gtk4` が引けていなかった | VTE の配置 |
| `fixups: 引けない名 __Znwm` | C++ の共有ライブラリが無かった。`operator new` は weak import になるので、リンカが静的書庫から引き込まない | libc++/libc++abi/libunwind を一枚にした `libc++.1.dylib` を新設 |
| 同上（dylib を置いても直らない） | 動的リンカが書き出しの表で弱い定義 (flags 0x04) を弾いていた | dyld の `trie_find` |
| `Failed to spawn ptyxis-agent: errno 43` | `socketpair()` が `SOCK_CLOEXEC`/`SOCK_NONBLOCK` を核へ素通ししていた（`socket()` には対処が入っていた） | libmiu。併せて記述子を作る 8 つの口を実機で測るゲートを新設 |

## パッチバージョニング

- 命名規則: `ptyxis-{VERSION}-r{N}`（例: `ptyxis-50.1-r1`）
- 各リビジョンはディレクトリ保存
- `patches/patch-*` は常に最新リビジョンのコピー

## 上流へのバグ報告

`upstream-patches/` に 2 枚。どちらも移植性の問題で、優先度は高。
提出手順は `upstream-patches/HOWTO_SUBMIT.md`。

未提出です。

## 動作確認済み機能

- [x] クロスビルド（エラー 0、警告のみ）
- [x] 上流 tarball への 2 パッチ適用（実測）
- [x] Mach-O / chained fixups / NOUNDEFS
- [x] 参照 dylib がすべて `/usr/lib/` を指す（`@rpath` なし）
- [x] イメージへの配置（依存 33 本すべて在庫確認）
- [x] `ptyxis-agent --help` が動く
- [x] `ptyxis` が `ptyxis-agent` を起こして接続する
- [ ] 窓の表示

## 次のアクション

1. **窓が出ない原因の切り分け** — 記録は VTE の regex 初期化まで進んで止まる。
   D-Bus の不在が原因かどうかはまだ確かめていない。GTK4 アプリ（MIU Darwin の
   greeter）は同じ D-Bus 警告を出しながら窓を出せているので、GApplication が
   D-Bus 無しで動くこと自体は確認済み。VTE の widget だけを出す最小のプログラムで
   切り分ける予定。
2. 上流への 2 枚の提出
3. 窓が出たら、複数タブ・端末操作の目視確認
