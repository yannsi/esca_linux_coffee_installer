# Esca Linux インストーラー（coffee 版）

Arch Linux を、日本語環境まで含めて対話形式で構築する bash スクリプトです。パーティション作成からデスクトップ環境・日本語入力・ログイン画面の設定までを一本で行います。

coffee 版は、オリジナルの [`install.sh`](https://github.com/yannsi/esca_linux_installer) から派生した版です。特定の機種向けではなく、デスクトップ環境を **COSMIC**、ログイン画面を **SDDM** の一本に固定しています。GPU（Intel / AMD / NVIDIA）や UEFI・BIOS は自動で判定します。

選べる組み合わせが多すぎて検証が追いつかず、大半が一度も動かさないまま残っていたため、構成を絞りました。他のデスクトップ環境が必要な場合は汎用版の `install.sh` を使ってください。

動作確認は dynabook T75/DG（Intel HD 620）で行っています。

> **警告**  
> このスクリプトは指定したディスクを丸ごと消去します。実行前に必ず対象ディスクを確認してください。動作は無保証です（LICENSE 参照）。

## 構成

| 項目 | 内容 |
| --- | --- |
| デスクトップ環境 | COSMIC（固定） |
| ログイン画面 | SDDM（固定） |
| 日本語入力 | fcitx5 + mozc（固定） |
| ファイルシステム | xfs（既定。ext4 / btrfs も選択可） |
| ブートローダー | systemd-boot（既定。GRUB も選択可、UEFI・BIOS 両対応） |
| パーティション | 自動 / 手動（fdisk） |
| ufw | 有効（既定） |
| OpenSSH | 無効（既定） |
| yt-fzf | 無効（既定） |
| 既定ターミナル | ghostty |

ディスク・ユーザー・ブートローダーなど環境ごとに変わる項目は、対話で選びます。

### Windows とのデュアルブート

選んだディスクに NTFS パーティションがあると Windows ありと判定し、ハードウェアクロックを localtime に合わせ、起動メニューに Windows を出す設定にします（質問はしません）。Windows を残す場合は、パーティション構成で必ず「手動（fdisk）」を選んで空き領域に作成してください。「自動」はディスク全体を消去します。

## テーマ

壁紙とログイン画面の配色を `--theme=` で切り替えられます。指定しなければ coffee です。

| 名前 | 表示名 |
| --- | --- |
| `coffee` | コーヒー（既定） |
| `aisumicha` | 藍墨茶 |
| `kakishibu` | 柿渋 |
| `kokemusu` | 苔むす |

```sh
bash install-coffee.sh --theme=kakishibu
bash install-coffee.sh --list-themes
```

## 日本語環境について

日本語で使うことを前提にしているため、次の項目は質問せずに固定しています。

- ロケール `ja_JP.UTF-8`、タイムゾーン `Asia/Tokyo`、キーマップ `jp106`
- 日本語入力は fcitx5 + mozc（切り替えは Ctrl + Space）
- 日本語フォントと Nerd Font を導入し、漢字が中国語字形にならないよう fontconfig を設定
- ミラーは reflector で日本のものを選択

COSMIC は独自のフォントデータベースで描画するため fontconfig の設定が効きません。シェル・テキストエディタ・ターミナルそれぞれに JP 付きフォントファミリを指定する設定を別途書き込みます。

## 必要なもの

- Arch Linux の公式インストールメディア（Live ISO）
- UEFI または BIOS で起動する PC
- インターネット接続（有線 / Wi-Fi のどちらでも可。Wi-Fi は対話中に設定できます）

## 使い方

Arch Linux の ISO で起動し、root で次を実行します。

```sh
pacman -Sy --noconfirm git
git clone https://github.com/yannsi/esca_linux_coffee_installer.git
cd esca_linux_coffee_installer
bash install-coffee.sh
```

あとは画面の指示に従って選択していきます。すべての選択が終わると設定の一覧が表示され、そこから項目ごとにやり直せます。最後に `YES` を大文字で入力すると実行が始まります。

### ドライラン

実際には何も書き換えずに、対話の流れと生成される設定ファイルを確認できます。

```sh
bash install-coffee.sh --dry-run
bash install-coffee.sh --help    # オプション一覧
```

知らないオプションを渡すと、何も始めずにエラーで終了します（打ち間違いのまま本番が動き出さないようにするため）。

生成物の確認先は実行開始時に表示されます（`/tmp` 以下の一時ディレクトリ）。

## 設定の引き継ぎ

インストール中に「設定の引き継ぎ元」を選べます。

| 選択 | 動作 |
| --- | --- |
| ホストPC | 実行元マシンの `~/.config` を探し、見つからなければ GitHub の dotfiles を取得 |
| GitHub | ホストを見ずに dotfiles リポジトリを取得 |
| なし | 各パッケージの既定設定のみ |

引き継ぎ元は既定で [esca-dotfiles](https://github.com/yannsi/esca-dotfiles) です。環境変数で差し替えられます。

```sh
ESCA_DOTFILES_REPO=https://github.com/user/dotfiles \
ESCA_DOTFILES_BRANCH=main \
bash install-coffee.sh
```

ローカルのディレクトリを直接使うこともできます。カスタム ISO に設定を同梱する場合はこちらが確実です。

```sh
ESCA_DOTFILES=/path/to/dotfiles bash install-coffee.sh
```

スクリプトと同じ場所に `dotfiles/` を置いておくと、それが最優先で使われます。

ディスプレイ構成（解像度・スケール・出力名）はマシン固有のため、引き継ぎ対象から除外しています。

## 画像ファイル

壁紙とログイン画面の背景は、スクリプトと同じ場所に置けばそれが使われます。

| ファイル | 用途 |
| --- | --- |
| `wallpaper-<テーマ名>.jpg` | デスクトップの壁紙 |
| `sddm-bg-<テーマ名>.jpg` | SDDM ログイン画面の背景 |

置かれていない場合は dotfiles リポジトリの直下から取得します（それぞれ `<テーマ名>` / `sddm-<テーマ名>`）。どちらも取得できなければ、壁紙はテーマの背景色で生成した単色になり、ログイン画面はテーマ色のグラデーションのみになります。

## インストール後

各ユーザーのホームに `はじめにお読みください.txt` が置かれます。日本語入力の切り替え方、パッケージの更新方法、壁紙の変更方法、ログインできなくなったときの復旧手順などをまとめてあります。不要になったら削除して構いません。

インストール時のログは `/var/log/` に保存されます。

## 動作環境と既知の制限

- COSMIC では LibreOffice のメニューが開かない問題があるため、ランチャーに環境変数を前置した上書き版を配置します
- 外付けディスクにインストールした場合、起動には UEFI/BIOS で起動順序の変更が必要です（手順は完了時に表示されます）
- Google Chrome は AUR からビルドします。失敗しても中断せず、手順を表示して続行します

## ライセンス

スクリプト本体は MIT ライセンスです（[LICENSE](LICENSE) を参照）。

壁紙・ログイン画面の背景画像は生成 AI を用いて作成したものを基にしており、MIT の対象には含めていません。再配布や商用利用を考える場合は各自でご判断ください。
