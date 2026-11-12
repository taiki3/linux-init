# linux-init

新しいLinux環境の初期ユーザー設定スクリプトです。

## 設定内容

- ユーザー `yoshinaka` の作成（ホームディレクトリ・`/bin/bash`・`sudo`/`wheel` グループ追加）
- パスワードなし `sudo` の有効化（`/etc/sudoers.d/90-yoshinaka`）
- SSH公開鍵（`id_ed25519.pub`）の `~/.ssh/authorized_keys` への登録とパーミッション・SELinuxコンテキスト設定

## 使い方

対象のLinux環境にSSH接続後、リポジトリをクローンして実行します（`root` または `sudo` 可能なユーザーで実行してください）。

```bash
git clone <REPO_URL>
cd linux-init
bash setup.sh
```
