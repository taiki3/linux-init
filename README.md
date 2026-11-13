# linux-init

新しいLinux環境の初期ユーザー設定スクリプトです。

## 設定内容

- ユーザー `yoshinaka` の作成（ホームディレクトリ・`/bin/bash`・`sudo`/`wheel` グループ追加）
- パスワードなし `sudo` の有効化（`/etc/sudoers.d/90-yoshinaka`）
- SSH公開鍵（`id_ed25519.pub`）の `~/.ssh/authorized_keys` への登録とパーミッション・SELinuxコンテキスト設定
- `yoshinaka` ユーザー環境への **Herdr** (`https://herdr.dev/install.sh`) と **Claude Code** (`https://claude.ai/install.sh`) の自動インストール（`~/.local/bin` の `PATH` 設定含む）
- **ヘッドレス化（GUI停止）**: `gdm3` を停止し `multi-user.target` に切り替えてユニファイドメモリを解放
- **OOM・ハング防止設定**: `earlyoom` の導入・設定（空きメモリ2%未満でLLMプロセスを優先停止）、`sshd` の OOM 保護（`OOMScoreAdjust=-1000`）、カーネルロックアップ時の自動再起動設定（`sysctl`）
- **Swap退避・キャッシュ解放**: `vm.swappiness=100`、ページキャッシュ解放（`drop_caches`）、`system.slice` のコールドメモリSwap退避（`memory.reclaim`）によりGPU/RDMAピン留め可能メモリを最大化

## 使い方

対象のLinux環境にSSH接続後、リポジトリをクローンして実行します（`root` または `sudo` 可能なユーザーで実行してください）。

```bash
git clone https://github.com/taiki3/linux-init.git
cd linux-init
./setup.sh
```

または `curl` で直接実行することも可能です。

```bash
curl -fsSL https://raw.githubusercontent.com/taiki3/linux-init/main/setup.sh | sudo bash
```
