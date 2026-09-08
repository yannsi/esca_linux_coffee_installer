# Esca Linux インストーラー（coffee 版）

Arch Linux を、日本語環境まで含めて対話形式で構築する bash スクリプトです。パーティション作成からデスクトップ環境・日本語入力・ログイン画面の設定までを一本で行います。

coffee 版は、オリジナルの `install.sh` から派生した個人向けプリセットです。対話の流れはオリジナルと同じで、既定値だけを実機（dynabook T75/DG, Intel HD 620）の構成に合わせてあります。Enter を押していけばその構成になり、番号を選び直せば他の構成にもできます。

> **警告**  
> このスクリプトは指定したディスクを丸ごと消去します。実行前に必ず対象ディスクを確認してください。動作は無保証です（LICENSE 参照）。

## coffee 版の既定値

| 項目 | 既定 |
| --- | --- |
| デスクトップ環境 | COSMIC |
| ディスプレイマネージャー | SDDM |
| ファイルシステム | xfs |
| ブートローダー | systemd-boot |
| ufw | 有効 |
| OpenSSH | 無効 |
| yt-fzf | 無効 |
| 既定ターミナル | ghostty |

壁紙とログイン画面の背景は、この選択に関係なく常に coffee 版のものになります。

## 選べる構成

- **デスクトップ環境**: なし / KDE Plasma / GNOME / Xfce / Budgie / COSMIC / Hyprland / Niri
- **ディスプレイマネージャー**: SDDM / GDM / LightDM / cosmic-greeter / greetd / なし（選んだ DE に応じて候補が変わります）
- **ファイルシステム**: ext4 / btrfs / xfs
- **ブートローダー**: systemd-boot / GRUB（UEFI・BIOS 両対応）
- **パーティション**: 自動 / 手動（fdisk）。Windows とのデュアルブートは手動を選んでください

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
git clone https://github.com/yannsi/esca-coffee.git
cd esca-coffee
bash install-coffee.sh
```

あとは画面の指示に従って選択していきます。すべての選択が終わると設定の一覧が表示され、そこから項目ごとにやり直せます。最後に `YES` を大文字で入力すると実行が始まります。

### ドライラン

実際には何も書き換えずに、対話の流れと生成される設定ファイルを確認できます。

```sh
bash install-coffee.sh --dry-run
```

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
| `wallpaper-coffee.jpg` | デスクトップの壁紙 |
| `sddm-bg-coffee.jpg` | SDDM ログイン画面の背景 |

置かれていない場合は dotfiles リポジトリの直下から取得します（それぞれ `coffee` / `sddm-coffee`）。どちらも取得できなければ、壁紙なし・ログイン画面はグラデーションのみになります。

## インストール後

各ユーザーのホームに `はじめにお読みください.txt` が置かれます。日本語入力の切り替え方、パッケージの更新方法、壁紙の変更方法、ログインできなくなったときの復旧手順などをまとめてあります。不要になったら削除して構いません。

インストール時のログは `/var/log/` に保存されます。

## 動作環境と既知の制限

- Hyprland / Niri でのログイン画面は greetd または SDDM を使ってください。GDM はこの組み合わせで黒画面になります
- COSMIC では LibreOffice のメニューが開かない問題があるため、ランチャーに環境変数を前置した上書き版を配置します
- 外付けディスクにインストールした場合、起動には UEFI/BIOS で起動順序の変更が必要です（手順は完了時に表示されます）
- Google Chrome は AUR からビルドします。失敗しても中断せず、手順を表示して続行します

## ライセンス

スクリプト本体は MIT ライセンスです（[LICENSE](LICENSE) を参照）。

壁紙・ログイン画面の背景画像は生成 AI を用いて作成したものを基にしており、MIT の対象には含めていません。再配布や商用利用を考える場合は各自でご判断ください。
