# 上流への提出方法

このディレクトリには Ptyxis の上流（GNOME GitLab）に提出すべき
プラットフォーム共通のバグ修正パッチが含まれています。

## 提出先

- プロジェクト: https://gitlab.gnome.org/chergert/ptyxis
- Issues: https://gitlab.gnome.org/chergert/ptyxis/-/issues
- Merge Requests: https://gitlab.gnome.org/chergert/ptyxis/-/merge_requests

## 提出するパッチ

| ファイル | 種別 | 優先度 |
|----------|------|--------|
| `0001-agent-do-not-force-link-glibc-on-non-linux.patch` | 移植性（非 Linux 全般） | 高 |
| `0002-tab-include-sys-wait-h-for-wait-macros.patch` | 移植性（非 glibc 全般） | 高 |

---

## 事前準備

### GNOME GitLab アカウント

https://gitlab.gnome.org/users/sign_in から GitLab.com アカウントでサインインするか、
新規アカウントを作成します。

### Personal Access Token

https://gitlab.gnome.org/-/profile/personal_access_tokens にアクセスし、
以下のスコープを持つトークンを作成します。

- `api` （Issue・MR の作成に必要）
- `read_repository` / `write_repository` （MR 用のフォーク操作に必要）

トークンを環境変数に設定するか、ファイルに保存します。

```sh
export GITLAB_TOKEN="glpat-xxxxxxxxxxxxxxxxxxxx"
```

または:

```sh
echo 'export GITLAB_TOKEN="glpat-xxxxxxxxxxxxxxxxxxxx"' > ~/.env-ptyxis-upstream
chmod 600 ~/.env-ptyxis-upstream
```

---

## 提出方法 A: Issue のみ（最短）

```sh
cd upstream-patches/
./create-issues.sh
```

スクリプトが対話的に 2 つの Issue を作成します。

---

## 提出方法 B: Issue + Merge Request（推奨）

### ステップ 1: Issue を作成

```sh
./create-issues.sh
```

作成された Issue の番号をメモしておきます（MR の説明文に記載するため）。

### ステップ 2: リポジトリをフォークしてパッチブランチを作成

```sh
./fork-and-prepare.sh
```

スクリプトが以下を自動実行します。

1. GNOME GitLab 上でフォークを作成（既存の場合はスキップ）
2. フォークをローカルにクローン（`./ptyxis-upstream-work/`）
3. パッチをブランチとして適用
4. フォークに push

### ステップ 3: Merge Request を作成

```sh
./create-mr.sh <issue1番号> <issue2番号>
# 例: ./create-mr.sh 123 124
```

---

## 提出方法 C: Web UI から手動提出

### Issue の作成

https://gitlab.gnome.org/chergert/ptyxis/-/issues/new を開き、
HOWTO_SUBMIT.md に記載のテンプレートを参考に 2 件作成します。

### MR の作成

```sh
# フォーク
# https://gitlab.gnome.org/chergert/ptyxis/-/forks/new

git clone https://gitlab.gnome.org/<your-username>/ptyxis.git
cd ptyxis

# ブランチ 1: 非 Linux で glibc を強制リンクしない
git checkout -b fix/no-force-link-glibc-non-linux
git am ../upstream-patches/0001-agent-do-not-force-link-glibc-on-non-linux.patch
git push origin fix/no-force-link-glibc-non-linux

# ブランチ 2: sys/wait.h の取り込み
git checkout main
git checkout -b fix/tab-include-sys-wait
git am ../upstream-patches/0002-tab-include-sys-wait-h-for-wait-macros.patch
git push origin fix/tab-include-sys-wait
```

GitLab Web UI で各ブランチから MR を作成します。

---

## Issue テンプレート

### Issue 1: 非 Linux x86_64 で glibc が強制リンクされる

タイトル: `agent: force_link_glibc_2.17.h is included on non-Linux x86_64 targets`

````markdown
## Summary

`agent/meson.build` includes `x86_64/force_link_glibc_2.17.h` whenever the CPU
family is x86_64, without checking which operating system is being targeted.

## Details

```meson
if target_machine.cpu_family() == 'x86_64'
  ptyxis_agent_c_args += ['-include', 'x86_64/force_link_glibc_2.17.h']
else
  libc_compat = false
```

The header pins glibc symbol versions. On an x86_64 system that does not use
glibc the agent therefore fails to build.

## Impact

Ptyxis cannot be built on non-glibc x86_64 platforms without a downstream
patch. Two ports carry the same fix independently: OpenBSD, and MIU Darwin
(a Darwin/XNU distribution with its own C library).

## Fix

```diff
-if target_machine.cpu_family() == 'x86_64'
+if target_machine.cpu_family() == 'x86_64' and host_machine.system() == 'linux'
```

`host_machine` rather than `target_machine`: in meson, `target_machine` only
carries a meaning when the artefact being built is itself a compiler. For an
application the machine the code runs on is `host_machine`. The two are
identical for a native build, so this is a no-op there, but they genuinely
differ under cross compilation.

## Affected versions

Confirmed in 49.3 and 50.1.
````

---

### Issue 2: sys/wait.h が取り込まれていない

タイトル: `tab: src/ptyxis-tab.c uses wait status macros without including <sys/wait.h>`

````markdown
## Summary

`src/ptyxis-tab.c` uses `WIFEXITED`, `WEXITSTATUS`, `WIFSIGNALED` and
`WTERMSIG` but never includes `<sys/wait.h>`.

## Details

POSIX places those macros in `<sys/wait.h>`. The file compiles on glibc only
because another header happens to pull it in. On systems whose headers follow
the POSIX placement more strictly, compilation fails.

## Impact

Ptyxis cannot be built without a downstream patch on such systems. Two ports
carry the same fix independently: OpenBSD, and MIU Darwin. Two ports hitting
the same omission independently suggests the include is genuinely missing
rather than either system being unusual.

## Fix

```diff
 #include <cairo.h>
+#include <sys/wait.h>
```

The include is harmless where the macros already arrive by another route.

## Affected versions

Confirmed in 49.3 and 50.1.
````

---

## コミットメッセージのスタイル

Ptyxis は `subject: description` 形式を使用します。

```
agent: do not force-link glibc symbols on non-Linux x86_64
tab: include <sys/wait.h> for the wait status macros
```

---

## フォローアップ

提出後は以下を確認します。

1. CI が通過しているか（パイプラインバッジ）
2. メンテナ（chergert）からのフィードバックがないか
3. マージされたら該当パッチを `miudarwin-port/patches/` から削除する
4. 次のリリースでパッチが含まれていることを確認する
