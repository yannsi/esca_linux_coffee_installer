#!/usr/bin/env bash
# ============================================
#  Esca Linux インストーラー（coffee版） — Arch Linux ベース・日本語環境セットアップ
#
#  coffee版について:
#  オリジナルの install.sh から派生した版。特定の機種向けではなく、
#  デスクトップ環境とログイン画面を COSMIC + SDDM の一本に固定してある。
#  （動作確認は dynabook T75/DG, Intel HD 620 で行っている）
#    デスクトップ = COSMIC（固定） / ログイン画面 = SDDM（固定） /
#    日本語入力 = fcitx5-mozc（固定） / ファイルシステム = xfs（既定） /
#    ufw = 有効 / OpenSSH = 無効 / yt-fzf-sh = 無効
#  ディスク・ユーザー・ブートローダーなど、環境ごとに変わる項目は
#  従来どおり対話で選ぶ。
#
#  【なぜ絞ったか】元は 8 種のデスクトップ環境と 5 種のログイン画面を
#  選べたが、組み合わせが多すぎて検証が追いつかず、大半は一度も
#  実行されないまま「動くはず」のコードとして残っていた。動かしていない
#  コードは壊れていても気付けないし、直しようもない。
#  実際に使う構成だけを残し、そのぶん COSMIC まわりを厚く見る方針にした。
#  他のデスクトップ環境が必要な場合は、汎用版の install.sh を使うこと。
# ============================================

set -euo pipefail
# -E (errtrace): ERR トラップを関数・サブシェルにも継承させる。
# これが無いと関数内で失敗したときにトラップが呼ばれず、原因不明のまま終了する。
set -E

# --- カラー定義 ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
GRAY='\033[0;90m'
MAGENTA='\033[0;35m'
RESET='\033[0m'

# --- テーマ定義 ---
# 【設計】テーマで変わるのは「色6つ + 画像ファイル名」だけ。処理の流れは共通で、
# 分岐は色定数の代入しか無い。これはデスクトップ環境の分岐（実機で確かめていない
# 経路が増える）とは性質が違い、増やしても壊れる余地がほとんど無いため、
# 1ファイルのまま切り替え式にしている。
#
# 色は左から順に次の役割:
#   sea_deep  背景の最も暗い部分 / ボタン文字の下地
#   sea_mid   背景グラデーションの中間
#   sea_light 背景グラデーションの明るい側
#   rod_light アクセント（入力欄のフォーカス枠・ボタン）
#   glow_gold 強調（現在は補助的に使用）
#   text_main 主要な文字色
#   text_dim  補助的な文字色（プレースホルダ等）
#
# 画像は「スクリプトと同じ場所の <local>」→「dotfiles リポジトリ直下の <remote>」
# の順に探す。どちらも無ければ sea_deep の単色壁紙を生成して使う。
declare -A THEME_DEFS=(
  [coffee]="コーヒー|#2b2b30|#3a2b1f|#4a3221|#d9b382|#e8c396|#f0e4c8|#c9ad82|wallpaper-coffee.jpg|coffee|sddm-bg-coffee.jpg|sddm-coffee"
  [aisumicha]="藍墨茶|#1b1f2a|#22304a|#2c4260|#7fa8c9|#a8cfe6|#e6eef5|#9fb4c6|wallpaper-aisumicha.jpg|aisumicha|sddm-bg-aisumicha.jpg|sddm-aisumicha"
  [kokemusu]="苔むす|#1e231d|#26332a|#33463a|#8fae86|#b9cfa8|#e9f0e2|#a8b8a0|wallpaper-kokemusu.jpg|kokemusu|sddm-bg-kokemusu.jpg|sddm-kokemusu"
  [kakishibu]="柿渋|#23201f|#2e2725|#3d3230|#c96a4a|#e08a63|#f2e6de|#c0a99c|wallpaper-kakishibu.jpg|kakishibu|sddm-bg-kakishibu.jpg|sddm-kakishibu"
)

# --- 引数解析 & ログ初期化 ---
_print_usage() {
  cat << USAGE_EOF
使い方: bash $(basename "$0") [オプション]

  --theme=<名前>   配色を指定する（既定: coffee）
  --list-themes    利用できるテーマの一覧を表示して終了する
  --dry-run        実際には書き換えず、対話と生成物の確認だけを行う
  -h, --help       このヘルプを表示して終了する
USAGE_EOF
}

_print_theme_list() {
  echo "利用できるテーマ:"
  local _t _label _rest
  for _t in "${!THEME_DEFS[@]}"; do
    IFS='|' read -r _label _rest <<< "${THEME_DEFS[$_t]}"
    printf '  %-12s %s\n' "$_t" "$_label"
  done
}

DRY_RUN="no"
THEME="coffee"
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN="yes" ;;
    --theme=*) THEME="${arg#--theme=}" ;;
    --list-themes) _print_theme_list; exit 0 ;;
    -h|--help) _print_usage; exit 0 ;;
    # 【重要】知らない引数は必ずここで止めること。
    # かつてこの分岐が無く、--list-them のような打ち間違いは黙って無視され、
    # そのまま本番のインストーラーが起動していた。ディスクを消すスクリプトで
    # 「オプションを間違えたのに動き出す」のは、警告を出さない分だけ危険。
    # 意図した動作にならなかったことを、何かを始める前に伝える。
    *)
      echo "不明なオプションです: ${arg}" >&2
      echo "" >&2
      _print_usage >&2
      exit 1
      ;;
  esac
done

if [[ -z "${THEME_DEFS[$THEME]:-}" ]]; then
  echo "不明なテーマです: ${THEME}" >&2
  echo "" >&2
  _print_theme_list >&2
  exit 1
fi

IFS='|' read -r THEME_LABEL \
  THEME_SEA_DEEP THEME_SEA_MID THEME_SEA_LIGHT \
  THEME_ROD_LIGHT THEME_GLOW_GOLD THEME_TEXT_MAIN THEME_TEXT_DIM \
  THEME_WALL_LOCAL THEME_WALL_REMOTE \
  THEME_SDDM_LOCAL THEME_SDDM_REMOTE <<< "${THEME_DEFS[$THEME]}"
readonly THEME THEME_LABEL
readonly THEME_SEA_DEEP THEME_SEA_MID THEME_SEA_LIGHT
readonly THEME_ROD_LIGHT THEME_GLOW_GOLD THEME_TEXT_MAIN THEME_TEXT_DIM
readonly THEME_WALL_LOCAL THEME_WALL_REMOTE THEME_SDDM_LOCAL THEME_SDDM_REMOTE

LOG_FILE="/tmp/esca-${THEME}-install-$(date +%Y%m%d-%H%M%S).log"

# --- /etc/skel の書き込み先 ---
# 【重要】ドライランでも設定生成の処理そのものは走る。パスを直書きしていると
# インストール先が未マウントの状態で Live 環境の ${SKEL_ROOT} に実ファイルを
# 作ってしまい、「変更は適用されません」という説明と食い違う。
# ドライラン時だけ書き込み先を一時ディレクトリへ逃がす。
# 生成物はそのまま残るので、何が書かれる予定かを実際に確認できる。
if [[ "$DRY_RUN" == "yes" ]]; then
  SKEL_ROOT="$(mktemp -d /tmp/esca-dryrun-skel-XXXXXX)"
else
  SKEL_ROOT="/mnt/etc/skel"
fi

# --- 設定を格納する連想配列 ---
declare -A CONFIG=(
  [disk]=""
  [disk_is_external]="no"
  [hostname]=""
  [timezone]="Asia/Tokyo"
  [locale]="ja_JP.UTF-8"
  [keymap]="jp106"
  [bootloader]="systemd-boot"
  [boot_mode]=""
  [partition_scheme]=""
  # 実際に使用する root / swap パーティション。do_format_and_mount で確定し、
  # do_chroot_config（resume フック判定）と do_bootloader（resume= 付与）で共用する。
  # swap_part が空文字なら「swap なし」を意味する。
  [root_part]=""
  [swap_part]=""
  [fs_type]="ext4"
  [desktop]="none"
  [dm]="none"
  # 設定の引き継ぎ元: host / git / none （step_config_source で選択）
  # 既定は host（ホストPC → GitHub → 無し の順に探す）
  [config_source]="host"
  [root_password]=""
  [users]=""
  [users_count]="0"
  [japanese_env]="yes"
  [jp_ime]="fcitx5-mozc"
  [wifi_backend]="none"
  [use_resolved]="no"
  [windows_found]="no"
  [extra_base_devel]="yes"
  [extra_zram]="yes"
  [extra_pkgs]=""
  [font_pkgs]="noto-fonts noto-fonts-cjk noto-fonts-emoji"
  [font_setup_fontconfig]="yes"
  [dry_run]="$DRY_RUN"
  [log_file]="$LOG_FILE"
  [gpu_driver]="none"
  [aur_helper]="yay"
  [extra_ssh]="yes"
  [extra_ufw]="no"
  [extra_fstrim]="yes"
  [install_chrome]="yes"
  [install_ytfzf]="yes"
  [install_office]="yes"
  [virt_env]="none"
  [cpu_vendor]=""
  [mirror_country]="Japan"
)

# パーティションデバイス名（nvme0n1 → nvme0n1p1, sda → sda1 など）
part_suffix() {
  local disk="$1"
  local num="$2"
  # /dev/ プレフィックスを除去して統一
  disk="${disk#/dev/}"
  if [[ "$disk" =~ nvme|mmcblk ]]; then
    echo "/dev/${disk}p${num}"
  else
    echo "/dev/${disk}${num}"
  fi
}

# このスクリプト自身が置かれているディレクトリ。
# ISO 同梱の dotfiles/ を探すのに使う。シンボリックリンク経由の起動でも実体を指すよう
# cd + pwd で解決する（dirname だけだと相対パスのまま返ることがある）。
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 設定の複製元となる「ホーム相当のディレクトリ」を返す。
#
# 【重要】Live ISO には /home にユーザーが存在しない。ホストPCの設定を既定に
# したくても、実ユーザーのホームを探す方法だけでは ISO から起動した瞬間に
# 何も見つからず、機能全体が無言でスキップされる。
# そこでインストーラと同じ場所に置いた dotfiles/ を最優先で見る。
# これなら設定を同梱したカスタム ISO を作るだけで複製が効く。
#
# 探索順:
#   1. 環境変数 ESCA_DOTFILES（明示指定。検証やCI用）
#   2. <スクリプトと同じ場所>/dotfiles          ← ISO 同梱用
#   3. sudo 実行元のホーム（SUDO_USER）
#   4. /home 直下の最初の実ユーザー
#   5. GitHub の dotfiles リポジトリを取得（最終手段。要ネットワーク）
#
# 【重要】3・4 は ".config を持っていること" を条件にする。
# Live ISO の /home は空か、あっても .config を持たない骨だけのことがある。
# 存在チェックだけで採用すると、中身が無いディレクトリを掴んだまま 5 に
# 到達できず、取得できるはずの設定が何も複製されない状態になる。
#
# 5 はネットワークに依存するため、この関数が空文字を返すことはありうる。
# 呼び出し側は「空文字 or 存在しないパス」を必ず安全に扱うこと。
#
# 【重要】ここで ~/dotfiles を優先してはいけない。
# dotfiles を git 管理して ~/.config/<app> からリンクを張る運用（同梱 setup.sh の方式）
# でも、リポジトリに入っているのは一部の設定だけで、rofi・fcitx5・mozc などは
# ホーム本体にしか無いのが普通。リポジトリ側を優先すると、そこに無い設定が
# 丸ごと複製対象から外れる（電源メニューのテーマが消える等）。
# ホーム本体を見れば「リンク済みのもの＝リポジトリの実体」も「リンクしていないもの」も
# 両方拾える。リンクの実体化は複製側の cp -aL が担当する。
#
# 返すのは「.config を含むディレクトリ」であること。呼び出し側は
# "$(_host_home)/.config/..." の形で参照する。
_host_home() {
  # ── 設定ソースの選択（step_config_source で設定）──
  # 【重要】ここ一箇所で分岐させることで、_host_home を参照している全ての
  # 呼び出し元（COSMIC・日本語入力・mpv などの設定複製）に一括で効く。
  # 呼び出し元はいずれも「空文字 or 存在しないパス」を安全に扱えるようになっている。
  #   host : ホストPC → GitHub → 無し（既定）
  #   git  : ホストPCを見ず、GitHub の dotfiles リポジトリを取得して使う
  #   none : 何も引き継がず、各パッケージの既定設定のみ使う
  local src="${CONFIG[config_source]:-host}"
  case "$src" in
    none)
      echo ""
      return
      ;;
    git)
      _git_dotfiles
      return
      ;;
  esac

  local found
  found=$(_host_home_raw)
  if [[ -n "$found" ]]; then
    echo "$found"
    return
  fi
  # ホスト側に設定が無い（＝素の Live ISO から起動した）場合は GitHub から取得する。
  # 取得にも失敗すれば空文字が返り、各パッケージの既定設定のみになる。
  _git_dotfiles
}

# ホストPC側の設定ディレクトリだけを探す（GitHub取得へのフォールバックはしない）。
# 見つからなければ空文字を返す。
# 【重要】CONFIG[config_source] を一切参照しないこと。
# step_config_source が「そもそもホスト設定が存在するか」を判定するために
# この関数を使うため、ここで分岐させると選択肢の提示が壊れる。
_host_home_raw() {
  if [[ -n "${ESCA_DOTFILES:-}" && -d "${ESCA_DOTFILES}/.config" ]]; then
    echo "${ESCA_DOTFILES}"
    return
  fi
  if [[ -d "${SCRIPT_DIR}/dotfiles/.config" ]]; then
    echo "${SCRIPT_DIR}/dotfiles"
    return
  fi
  if [[ -n "${SUDO_USER:-}" && -d "/home/${SUDO_USER}/.config" ]]; then
    echo "/home/${SUDO_USER}"
    return
  fi
  local d
  for d in /home/*; do
    [[ -d "$d/.config" ]] || continue
    echo "$d"
    return
  done
  echo ""
}

# GitHub 上の dotfiles リポジトリを取得し、そのディレクトリのパスを返す
# （失敗時は空文字）。
#
# 【重要】mktemp -d を使わず固定パスにすること。
# _host_home() は "$(_host_home)" の形でサブシェルから何度も呼ばれるため、
# 取得先をグローバル変数にキャッシュしても呼び出し元には伝わらない。
# mktemp だと呼ばれるたびに clone し直すことになる。
# 固定パスなら 2回目以降は取得済みのものをそのまま再利用できる。
#
# 【重要】この関数は「パス」を標準出力で返す契約になっている。
# git / curl の進捗表示が stdout に混ざるとパスが壊れるため、
# 取得コマンドの出力は必ず捨てること。
ESCA_DOTFILES_REPO="${ESCA_DOTFILES_REPO:-https://github.com/yannsi/esca-dotfiles}"
ESCA_DOTFILES_BRANCH="${ESCA_DOTFILES_BRANCH:-main}"

_git_dotfiles() {
  local d="/tmp/esca-git-dotfiles"

  # 取得済みならそのまま使う
  if [[ -d "$d/.config" && ! -L "$d" ]]; then
    echo "$d"
    return
  fi

  # 前回の中断で壊れた残骸やシンボリックリンクが居座っている場合に備えて作り直す
  [[ -L "$d" ]] && rm -f "$d"
  rm -rf "$d"

  # 1) git があれば git clone（--depth=1 で履歴は取らない）
  if command -v git > /dev/null 2>&1; then
    if git clone --depth=1 --branch "$ESCA_DOTFILES_BRANCH" \
         "$ESCA_DOTFILES_REPO" "$d" > /dev/null 2>&1; then
      # .git は不要（そのままだと各ユーザーのホームに .git が配られてしまう）
      rm -rf "$d/.git"
      [[ -d "$d/.config" ]] && { echo "$d"; return; }
    fi
    rm -rf "$d"
  fi

  # 2) git が無い / clone に失敗した場合は tarball を取得する。
  # Live ISO に git が入っていない構成でも curl はほぼ確実にあるため、
  # ここまで用意しておくと「ネットワークはあるのに取得できない」を減らせる。
  if command -v curl > /dev/null 2>&1; then
    local tarball="/tmp/esca-git-dotfiles.tar.gz"
    local tmpx="/tmp/esca-git-dotfiles-x"
    rm -rf "$tmpx" "$tarball"
    if curl -fsSL "${ESCA_DOTFILES_REPO}/archive/refs/heads/${ESCA_DOTFILES_BRANCH}.tar.gz" \
         -o "$tarball" > /dev/null 2>&1; then
      mkdir -p "$tmpx" 2>/dev/null || { echo ""; return; }
      if tar xzf "$tarball" -C "$tmpx" > /dev/null 2>&1; then
        # tarball は "<repo>-<branch>/" という1階層でくるまれている
        local inner
        inner=$(find "$tmpx" -mindepth 1 -maxdepth 1 -type d | head -n1)
        if [[ -n "$inner" && -d "$inner/.config" ]]; then
          mv "$inner" "$d" 2>/dev/null && {
            rm -rf "$tmpx" "$tarball"
            echo "$d"
            return
          }
        fi
      fi
    fi
    rm -rf "$tmpx" "$tarball"
  fi

  rm -rf "$d"
  echo ""
}

# ============================================
# 壁紙
# ============================================
# Esca の壁紙をターゲットへ配置し、その「インストール先の絶対パス」を返す
# （配置できなければ空文字）。返すのは /mnt を含まないターゲット視点のパス。
#
# 【重要】この関数は「パス」を標準出力で返す契約。
# 進捗表示やエラーを stdout に混ぜないこと。
#
# 探索順:
#   1. 引き継ぎ元 dotfiles の esca / esca.png（GitHub 取得やホストPCから来たもの）
#   2. GitHub から直接ダウンロード（1 が無い＝引き継ぎ「なし」を選んだ場合など）
# 壁紙の配置先。
# 【重要】拡張子は中身と一致させること。coffee 版の壁紙は JPEG なので .jpg。
# 以前は esca 時代の名残で JPEG を esca.png として置いていた。cosmic-bg は
# 内容でフォーマットを判定するので実害は出ていなかったが、拡張子でデコーダを
# 選ぶ実装（他の壁紙デーモンやサムネイラ）に当たると読めずに黙って背景が
# 黒くなる。ファイルを見た人が混乱する元でもある。
WALLPAPER_DEST="/usr/share/backgrounds/esca/${THEME}.jpg"

# GitHub から取得したバイナリを /tmp にキャッシュしつつ、そのパスを返す
# （取得できなければ空文字）。
#
# 【重要】キャッシュの存在確認だけで再利用しないこと。
# 前回の実行が転送中に中断されると、0 バイトや途中までのファイルが残る。
# それをそのまま配置すると「壁紙が真っ黒」「グリフが豆腐のまま」という、
# 原因の分かりにくい形で失敗する。中身を検証し、壊れていれば取り直す。
#
# 引数1: キャッシュ先のパス / 引数2: 取得元 URL
# 引数3: 期待する先頭バイト列（省略可） / 引数4: 期待する末尾付近のバイト列（省略可）
_fetch_cached() {
  local tmp="$1" url="$2" magic="${3:-}" trailer="${4:-}"

  _valid() {
    [[ -s "$1" ]] || return 1
    if [[ -n "$magic" ]]; then
      # 【重要】マジックバイトが指定されている場合はサイズで足切りしないこと。
      # かつて同梱していた EscaSymbols.otf はグリフ1個だけの約 1.2KB しかなく、
      # 「1KB 未満は不正」のような閾値を入れると正当なフォントを弾いた。
      # （このフォント自体は廃止したが、小さい正当ファイルは今後もありうる）
      [[ "$(head -c "${#magic}" "$1" 2>/dev/null)" == "$magic" ]] || return 1
    elif [[ "$(stat -c %s "$1" 2>/dev/null || echo 0)" -lt 512 ]]; then
      # 形式を確認できない場合のみ、HTML のエラーページ等を弾く目的で
      # 最低限のサイズを見る
      return 1
    fi
    # 【重要】先頭だけ見ても「転送が途中で切れたファイル」は検出できない。
    # 元々防ぎたいのは中断されたダウンロードの再利用なので、
    # 終端マーカーを持つ形式では末尾も必ず確認する。
    #
    # trailer に "JPEG" を渡した場合だけは特別扱いし、末尾2バイトが
    # EOI マーカー (FF D9) かを od で見る。JPEG の終端は印字可能文字ではなく、
    # grep -F にバイナリを渡すと環境によって取りこぼすため。
    if [[ "$trailer" == "JPEG" ]]; then
      [[ "$(tail -c 2 "$1" 2>/dev/null | od -An -tx1 | tr -d ' \n')" == "ffd9" ]] || return 1
    elif [[ -n "$trailer" ]]; then
      tail -c 16 "$1" 2>/dev/null | grep -qF -- "$trailer" || return 1
    fi
    return 0
  }

  if [[ -f "$tmp" ]] && _valid "$tmp"; then
    unset -f _valid
    echo "$tmp"
    return
  fi
  rm -f "$tmp"

  command -v curl > /dev/null 2>&1 || { unset -f _valid; echo ""; return; }
  if curl -fsSL "$url" -o "$tmp" > /dev/null 2>&1 && _valid "$tmp"; then
    unset -f _valid
    echo "$tmp"
    return
  fi
  rm -f "$tmp"
  unset -f _valid
  echo ""
}

# テーマの背景色で単色の壁紙を生成し、その配置先パスを標準出力に返す。
#
# 【なぜ画像を作るのか】cosmic-bg の設定は単色の指定にも対応しているが、
# その RON の書き方を実機で確かめられていない。書式を間違えるとパースに
# 失敗して既定の壁紙に戻るだけで、エラーは出ない（filter_by_theme を
# #true と書いていた頃と同じ壊れ方をする）。
# 画像ファイルを指す Path() は実機で動作を確認済みの経路なので、
# 単色でも画像を作ってそちらに寄せる。
#
# imagemagick は do_pacstrap でターゲットに導入済み。
_generate_solid_wallpaper() {
  if [[ "${CONFIG[dry_run]}" == "yes" ]]; then
    echo "$WALLPAPER_DEST"
    return
  fi

  if [[ ! -x /mnt/usr/bin/magick ]]; then
    print_warn "  imagemagick が見つからないため生成できませんでした。壁紙は設定しません。" >&2
    echo ""
    return
  fi

  mkdir -p "/mnt$(dirname "$WALLPAPER_DEST")" 2>/dev/null || { echo ""; return; }
  if arch-chroot /mnt magick -size 1920x1080 "xc:${THEME_SEA_DEEP}" \
       "$WALLPAPER_DEST" > /dev/null 2>&1; then
    chmod 644 "/mnt${WALLPAPER_DEST}" 2>/dev/null || true
    echo "$WALLPAPER_DEST"
  else
    print_warn "  単色壁紙の生成に失敗しました。壁紙は設定しません。" >&2
    echo ""
  fi
}

_install_wallpaper() {
  local src=""

  # スクリプトと同じ場所にテーマの壁紙があれば最優先で使う
  # （ホストPC/GitHub 探索より先に、このスクリプト専用の壁紙を採用する）
  if [[ -f "${SCRIPT_DIR}/${THEME_WALL_LOCAL}" ]]; then
    src="${SCRIPT_DIR}/${THEME_WALL_LOCAL}"
  fi

  # ローカルに無ければ、dotfiles リポジトリのルートに置いた画像を取得する。
  #
  # 【重要】JPEG のマジックバイト（\xFF\xD8）と終端の EOI (\xFF\xD9) の両方で
  # 検証する。以前はサイズ512バイト以上という緩い足切りしかしておらず、
  # 取得先が HTML のエラーページ等にすり替わっていても「成功」扱いに
  # なりかねなかった。さらに壁紙は 1MB 超あるため転送が途中で切れやすく、
  # 先頭だけ見ていると壊れたファイルが /tmp に居座って再取得もされない。
  if [[ -z "$src" ]]; then
    src=$(_fetch_cached "/tmp/esca-${THEME}-wallpaper.jpg" \
      "https://raw.githubusercontent.com/${ESCA_DOTFILES_REPO#https://github.com/}/${ESCA_DOTFILES_BRANCH}/${THEME_WALL_REMOTE}" \
      "$(printf '\xFF\xD8')" "JPEG")
  fi

  # 【重要】他テーマの画像へフォールバックしないこと。
  # 「壁紙は常に選んだテーマのものを使う（config_source の選択と無関係）」という
  # 方針を掲げており、step_config_source でも利用者にそう説明している。
  # 以前は取得に失敗すると警告1行だけ出して黙って別の壁紙に切り替わっており、
  # 掲げた方針と食い違ったまま「なぜか見覚えのない壁紙になる」状態になっていた。
  #
  # 画像が用意されていないテーマもあるため、その場合は
  # デスクトップ環境の既定（COSMIC なら星雲の写真）に落とすのではなく、
  # テーマの背景色で単色の壁紙を生成する。配色と無関係な写真が出るより、
  # 単色のほうがテーマとして筋が通る。
  if [[ -z "$src" ]]; then
    # 【重要】この関数は「パス」を標準出力で返す契約なので、警告は必ず
    # 標準エラーへ出すこと。print_warn は stdout に書くため、そのまま呼ぶと
    # 警告文が戻り値に混ざり、呼び出し元が壊れたパスを設定ファイルに
    # 埋め込んでしまう。
    print_warn "${THEME_LABEL} の壁紙画像が見つかりませんでした。" >&2
    print_warn "  探索先1: ${SCRIPT_DIR}/${THEME_WALL_LOCAL}" >&2
    print_warn "  探索先2: ${ESCA_DOTFILES_REPO} の ${ESCA_DOTFILES_BRANCH} ブランチ直下の ${THEME_WALL_REMOTE}" >&2
    print_warn "  代わりにテーマの背景色 ${THEME_SEA_DEEP} で単色の壁紙を生成します。" >&2
    _generate_solid_wallpaper
    return
  fi

  # 【重要】ここは run_cmd を通さず直接 /mnt に書くため、ドライラン判定を
  # 自前で持つ必要がある。未マウントの状態で書くと Live ISO 側のルートに
  # 実ファイルができてしまい、「変更は適用されません」という説明と食い違う。
  # ただしパスは返す。呼び出し元はこの値を設定ファイルに埋め込むので、
  # 空文字を返すとドライランでの生成物が本番と別物になってしまう。
  if [[ "${CONFIG[dry_run]}" == "yes" ]]; then
    echo "$WALLPAPER_DEST"
    return
  fi

  # 取得元は拡張子なしの "coffee" で配布されているため、配置先で .jpg を付ける。
  mkdir -p "/mnt$(dirname "$WALLPAPER_DEST")" 2>/dev/null || { echo ""; return; }
  if cp "$src" "/mnt${WALLPAPER_DEST}" 2>/dev/null; then
    chmod 644 "/mnt${WALLPAPER_DEST}" 2>/dev/null || true
    echo "$WALLPAPER_DEST"
  else
    echo ""
  fi
}

# 引き継いだ starship 設定から Esca 専用グリフを取り除く。
#
# 【経緯】以前は独自フォント EscaSymbols.otf を U+100000 に配置し、
# fontconfig のフォールバックで拾わせていた。しかし実機の GNOME では
# どうしても豆腐(□)のままで表示できなかった。
# fontconfig の match 対象を monospace 限定から全パターンに広げても解決せず、
# 私用領域(PUA)の符号位置はレンダラ側がフォールバックを拒否することがあり
# （PUA は意味が未定義なため、システムフォールバックを行わない実装がある）、
# 環境ごとの当たり外れを完全には制御できない。
#
# 【判断】「特定環境で豆腐になる独自グリフ」より
# 「どこでも確実に出る標準の記号」を優先する。ブランディングのために
# 利用者のプロンプトが壊れるのは本末転倒なので、独自フォントは廃止した。
#
# dotfiles 側の starship.toml には U+100000 が直接書き込まれているため、
# 引き継いだ場合はここで Nerd Fonts の Linux アイコン (U+F17C) に置換する。
_strip_esca_glyph() {
  local f="${SKEL_ROOT}/.config/starship.toml"
  [[ -f "$f" ]] || return 0

  # 【重要】U+100000 は UTF-8 で 4 バイト (f4 80 80 80)。
  # printf '\U100000' はロケール依存で C ロケールだと展開されないため、
  # Nerd Font のアイコンと同じくバイト列で直接指定する。
  local esca linux_icon
  esca=$(printf '\xf4\x80\x80\x80')
  linux_icon=$(printf '\xef\x85\xbc')   # U+F17C nf-fa-linux

  grep -q "$esca" "$f" 2>/dev/null || return 0

  run_cmd_soft "starship: Esca グリフを標準アイコンに置換" \
    sed -i "s/${esca}/${linux_icon}/g" "$f" || true

  # 説明コメントも実態と合わなくなるので併せて落とす。
  run_cmd_soft "starship: 廃止したフォントへの言及を削除" \
    sed -i '/EscaSymbols\.otf/d' "$f" || true

  print_ok "starship のプロンプト記号を標準アイコンに統一しました"
}

# 引き継いだ starship 設定のうち、Nerd Fonts v3 で削除された符号位置を差し替える。
#
# 【重要】v3 は U+F500-FD46 を廃止した。v2 時代の設定をそのまま持ち込むと、
# フォントは入っているのにその文字だけ豆腐(□)になる。
_fix_starship_nerdfont_v3() {
  local f="${SKEL_ROOT}/.config/starship.toml"
  [[ -f "$f" ]] || return 0

  # U+F83D (v3 で削除) -> U+F023 (nf-fa-lock, v3 でも有効)
  local old_lock new_lock
  old_lock=$(printf '\xef\xa0\xbd')
  new_lock=$(printf '\xef\x80\xa3')

  grep -q "$old_lock" "$f" 2>/dev/null || return 0
  run_cmd_soft "starship: Nerd Fonts v3 で削除された符号位置を置換" \
    sed -i "s/${old_lock}/${new_lock}/g" "$f" || true
  print_ok "starship: 廃止された符号位置のアイコンを現行のものに差し替えました"
}

# COSMIC の壁紙エントリ（RON）を組み立てて標準出力に返す。
# 引数1: 壁紙の絶対パス（ターゲット視点）
#
# 【重要】書式は RON。真偽値は true / false と書くこと。
# 以前ここを #true と書いていたが、# は #![enable(...)] という拡張宣言でしか
# 使わない記法で、値としては不正。パースに失敗すると cosmic-bg は
# Entry::fallback()（/usr/share/backgrounds/cosmic/orion_nebula_*.jpg）に落ちる
# ため、「設定は書いたのに既定の壁紙のまま」という分かりにくい壊れ方をする。
#
# filter_by_theme はライト/ダークで画像を選び分ける機能で、source が
# ディレクトリのときに意味がある。ここは単一ファイルなので false。
_cosmic_background_entry() {
  cat << EOF
(
    output: "all",
    source: Path("${1}"),
    filter_by_theme: false,
    rotation_frequency: 3600,
    filter_method: Lanczos,
    scaling_mode: Zoom,
    sampling_method: Alphanumeric,
)
EOF
}

# COSMIC の壁紙をユーザー設定（/etc/skel）としても焼き込む。
#
# 【重要】/usr/share/cosmic/com.system76.CosmicBackground/v1/all は cosmic-bg
# パッケージが所有するファイル。そこだけに書くと、次に cosmic-bg が更新された
# 時点で pacman に上書きされ、壁紙が既定に戻る（設定した本人には原因が
# 分からない形で戻る）。ユーザー設定はパッケージ更新の影響を受けず、かつ
# システム既定より優先されるので、両方に置いておく。
#
# 【順序注意】do_desktop のホスト設定コピーは
# ${SKEL_ROOT}/.config/cosmic/com.system76.CosmicBackground を一度削除する。
# そのため、この関数は削除処理より後にもう一度呼ぶ必要がある。
COSMIC_WALLPAPER_PATH=""
write_cosmic_wallpaper_config() {
  [[ "${CONFIG[dry_run]}" == "yes" ]] && return 0
  [[ -z "$COSMIC_WALLPAPER_PATH" ]] && return 0

  local dir="${SKEL_ROOT}/.config/cosmic/com.system76.CosmicBackground/v1"
  mkdir -p "$dir" || return 0
  _cosmic_background_entry "$COSMIC_WALLPAPER_PATH" > "${dir}/all"
  # same-on-all の既定は true だが、明示しておくと「all を読むはず」の前提が
  # ファイルとして残り、後から追った人が迷わない。
  printf 'true\n' > "${dir}/same-on-all"
}

# 壁紙を COSMIC のシステム既定として設定する。
# 引数1: 壁紙のインストール先パス（ターゲット視点）
#
# 【方針】可能な限り「ユーザーのホーム」ではなく「システム既定」として設定する。
# skel に置く方式は、インストール後に作った2人目以降のユーザーや、DE 側が初回
# ログイン時に設定を再生成するケースで効かないことがあるため。
_set_de_wallpaper() {
  local wp="$1"
  [[ -z "$wp" ]] && return 0

  # cosmic-bg はシステム既定を /usr/share/cosmic/ 配下から読む
  # （パッケージ自身が同じ場所に既定値を置いている）。
  # 書式と RON の注意点は _cosmic_background_entry のコメントを参照。
  COSMIC_WALLPAPER_PATH="$wp"
  if [[ "${CONFIG[dry_run]}" != "yes" ]]; then
    run_cmd "壁紙: COSMIC システム既定を配置" bash -c "
      mkdir -p /mnt/usr/share/cosmic/com.system76.CosmicBackground/v1
      cat > /mnt/usr/share/cosmic/com.system76.CosmicBackground/v1/all << 'RONEOF'
$(_cosmic_background_entry "$wp")
RONEOF
    "
  fi
  # 【重要】/usr/share 側は cosmic-bg パッケージが所有するファイルなので、
  # cosmic-bg が更新されると pacman に上書きされて壁紙が既定に戻る。
  # ユーザー設定としても焼き込んでおく（優先度も高く、更新の影響も受けない）。
  write_cosmic_wallpaper_config

  # 設定は書けても画像が無ければ cosmic-bg は既定の壁紙に落ちる。
  # 「設定は正しいのに反映されない」の切り分けができるよう明示する。
  if [[ "${CONFIG[dry_run]}" != "yes" && ! -f "/mnt${wp}" ]]; then
    print_warn "壁紙: 設定は書き込みましたが /mnt${wp} が見当たりません。COSMIC の既定壁紙のまま起動する可能性があります。"
  else
    print_ok "壁紙: COSMIC の既定壁紙を設定しました"
  fi
}

# ============================================
# 一時 sudoers の後始末
# ============================================
# do_aur_helper は makepkg を非対話で回すため、対象ユーザーに一時的な
# NOPASSWD sudo を付与する。正常系では関数末尾で削除するが、AUR ビルドは
# 失敗しやすく、途中で異常終了すると「パスワード不要 sudo」が入ったままの
# システムが出来上がってしまう。そのため trap で確実に消す。
# ※ パスはグローバル変数に置く。local 変数を trap 文字列で参照すると、
#    EXIT 時には既に消えていて rm -f "/mnt" になりかねない。
AUR_TEMP_SUDOERS=""


_cleanup_temp_sudoers() {
  if [[ -n "${AUR_TEMP_SUDOERS:-}" ]] && [[ -e "/mnt${AUR_TEMP_SUDOERS}" ]]; then
    rm -f "/mnt${AUR_TEMP_SUDOERS}" 2>/dev/null || true
  fi
}

_on_interrupt() {
  _cleanup_temp_sudoers
  exit 130
}

# ============================================
# 予期しない終了の可視化
# ============================================
# set -e で停止すると何も表示されずにプロンプトへ戻るため、
# 「何も言わずに終了した」ように見えてしまう。どこで何が失敗したかを必ず出す。
_on_error() {
  local rc=$?
  # 【重要】ハンドラ内の $LINENO は「ハンドラ自身の行」になるため使えない。
  # 実際に失敗したコマンドの行は BASH_LINENO[0]、その呼び出し元は BASH_LINENO[1]。
  # ここを取り違えると、毎回この関数の行番号が「発生場所」として表示され、
  # 報告を受けても原因箇所に辿り着けなくなる。
  local line="${BASH_LINENO[0]:-?}"
  local caller_line="${BASH_LINENO[1]:-?}"
  local fn="${FUNCNAME[1]:-main}"
  echo ""
  echo -e "${RED}${BOLD}✘ 予期しないエラーで停止しました${RESET}"
  echo -e "${RED}  終了コード  : ${rc}${RESET}"
  echo -e "${RED}  失敗した処理: ${BASH_COMMAND}${RESET}"
  echo -e "${RED}  発生場所    : ${fn}() の ${line} 行目${RESET}"
  echo -e "${RED}  呼び出し元  : ${caller_line} 行目${RESET}"
  echo -e "${RED}  ログ        : ${CONFIG[log_file]:-未作成}${RESET}"
  echo ""
  echo -e "  ${GRAY}この内容をそのまま報告すると原因を特定できます。${RESET}"
  _cleanup_temp_sudoers
}

# ============================================
# ユーティリティ関数
# ============================================

# ============================================
# ブランディング
# ============================================
# Esca — チョウチンアンコウの発光する疑似餌。
# 深海で道を照らす光、という含意でこの名前にしている。
#
# 【重要】曲線部分に ╭ ╰ ╱ ● といった文字を使わないこと。
# Live ISO の VGA コンソールフォント（CP437 系）に含まれず、
# 化けて意味不明な表示になる。ASCII の . , ' - / \ で描く。
# 一方 █ ╔ ╗ ╚ ╝ ═ ║ ─ │ は CP437 に含まれるので安全。

readonly OS_NAME="Esca Linux"
readonly OS_ID="esca"
readonly OS_TAGLINE="日本語環境セットアップ ・ ${THEME_LABEL}"
# 【重要】プロジェクトの公開 URL。os-release と SDDM テーマの両方から参照する。
# os-release に書いた値はインストールした全システムに残り続けるため、
# 実在しない URL を入れると利用者側で恒久的にリンク切れになる。
# 2箇所に直書きすると片方だけ直し忘れるので、必ずここで一元管理すること。
readonly OS_HOME_URL="https://github.com/yannsi/esca_linux_installer"

# 起動時に一度だけ表示する大きいロゴ
print_logo() {
  clear
  echo ""
  echo -e "                    ${YELLOW}${DIM}. ${BOLD}*${RESET}${YELLOW}${DIM} .${RESET}"
  echo -e "                  ${YELLOW}${DIM}*${RESET}  ${YELLOW}${BOLD}(o)${RESET}  ${YELLOW}${DIM}*${RESET}"
  echo -e "                    ${YELLOW}${DIM}. ${BOLD}*${RESET}${YELLOW}${DIM} .${RESET}"
  echo -e "                      ${CYAN}|${RESET}"
  echo -e "               ${CYAN},------'${RESET}"
  echo -e "             ${CYAN},'${RESET}"
  echo -e "        ${CYAN}----'${RESET}"
  echo ""
  echo -e "  ${CYAN}${BOLD}███████╗███████╗ ██████╗ █████╗ ${RESET}"
  echo -e "  ${CYAN}${BOLD}██╔════╝██╔════╝██╔════╝██╔══██╗${RESET}"
  echo -e "  ${CYAN}${BOLD}█████╗  ███████╗██║     ███████║${RESET}"
  echo -e "  ${CYAN}${BOLD}██╔══╝  ╚════██║██║     ██╔══██║${RESET}"
  echo -e "  ${CYAN}${BOLD}███████╗███████║╚██████╗██║  ██║${RESET}"
  echo -e "  ${CYAN}${BOLD}╚══════╝╚══════╝ ╚═════╝╚═╝  ╚═╝${RESET}"
  echo ""
  echo -e "     ${DIM}Arch Linux ベース${RESET}  ${GRAY}·${RESET}  ${DIM}${OS_TAGLINE}${RESET}"
  echo ""
}

# 各ステップで表示するコンパクトなヘッダー。
# print_step から毎回呼ばれ画面をクリアするため、大きいロゴは使わない。
print_header() {
  clear
  echo ""
  echo -e "  ${YELLOW}${BOLD}(o)${RESET} ${CYAN}${BOLD}${OS_NAME}${RESET}  ${GRAY}│${RESET}  ${DIM}${OS_TAGLINE}${RESET}"
  echo -e "  ${CYAN}$(printf '━%.0s' {1..48})${RESET}"
  echo ""
}

print_step() {
  print_header
  if [[ "${STEP_TOTAL:-0}" -gt 0 ]]; then
    # 直前ステップの所要時間を記録（完了画面のサマリー用）
    if [[ -n "${CURRENT_STEP_NAME:-}" ]]; then
      STEP_LOG+=("${CURRENT_STEP_NAME}|$(( SECONDS - CURRENT_STEP_TS ))")
    fi
    CURRENT_STEP_NAME="$1"
    CURRENT_STEP_TS=$SECONDS
    STEP_NUM=$(( ${STEP_NUM:-0} + 1 ))
    echo -e "  ${MAGENTA}${BOLD}[${STEP_NUM}/${STEP_TOTAL}]${RESET} ${BLUE}${BOLD}▶ $1${RESET}"
    if [[ -n "${INSTALL_START:-}" ]]; then
      echo -e "  ${GRAY}経過時間: $(( (SECONDS - INSTALL_START) / 60 ))分$(( (SECONDS - INSTALL_START) % 60 ))秒${RESET}"
    fi
  else
    echo -e "  ${BLUE}${BOLD}▶ $1${RESET}"
  fi
  echo -e "  ${BLUE}${DIM}$(printf '─%.0s' {1..48})${RESET}"
  echo ""
}

print_ok()   { echo -e "  ${GREEN}✔${RESET} $1"; }
print_warn() { echo -e "  ${YELLOW}⚠${RESET} $1"; }
print_err()  { echo -e "  ${RED}✘${RESET} $1"; }

# 出力/入力に使う tty を解決する（/dev/tty が使えなければ stderr/stdin へフォールバック）。
# 使い方: local tty_out tty_in; _resolve_tty tty_out tty_in
_resolve_tty() {
  local -n _out_ref="$1" _in_ref="$2"
  _out_ref="/dev/tty"; [[ -w /dev/tty ]] || _out_ref="/dev/stderr"
  _in_ref="/dev/tty";  [[ -r /dev/tty ]] || _in_ref="/dev/stdin"
}

# 対話入力の共通読み取り。
# 素の `read` は EOF（パイプ実行・Ctrl+D・端末喪失）で非ゼロを返し、
# set -e により何のメッセージも出さずスクリプトが終了してしまう。
# 「何も言わず終了した」ように見える事故を防ぐため、必ずここを通す。
_read_input() {
  local -n _dest_ref="$1"
  local src="$2" dst="$3" mode="${4:-normal}"
  local rc=0
  if [[ "$mode" == "silent" ]]; then
    read -rs _dest_ref < "$src" || rc=$?
  else
    read -r _dest_ref < "$src" || rc=$?
  fi
  if [[ "$rc" -ne 0 ]]; then
    echo "" > "$dst"
    echo -e "  ${RED}✘ 入力を読み取れませんでした（入力が尽きたか、端末が切断されました）。${RESET}" > "$dst"
    echo -e "  ${GRAY}このスクリプトは対話式です。パイプ経由ではなく直接実行してください。${RESET}" > "$dst"
    echo -e "  ${GRAY}例: sudo bash $(basename "$0")${RESET}" > "$dst"
    exit 1
  fi
  _dest_ref="${_dest_ref:-}"
}

# コマンドをバックグラウンドで実行しつつ、5秒を超えたら経過時間を毎秒表示する。
# 長時間コマンド（pacstrap 等）がフリーズと区別できるようにするための内部ヘルパー。
# 終了コードをそのまま返す（exit はしない）。最終行の確定表示は呼び出し側が行う。
# まだディスクに書き戻されていないページキャッシュの量（MiB）を返す。
# Dirty  : 変更済みでまだ書き出していない分
# Writeback: いま書き出している最中の分
# この2つが 0 に近づけば、sync / umount はもうすぐ終わる。
_dirty_mib() {
  awk '/^(Dirty|Writeback):/ { s += $2 } END { printf "%d", s / 1024 }' /proc/meminfo 2>/dev/null || echo "?"
}

# ライブ環境のライトバック閾値を下げ、書き込みを install 中に分散させる。
#
# 【経緯】既定では「RAM の 10〜20%」まで未書き込みのページを溜めてから
# 書き戻す。pacstrap やデスクトップ環境の導入で数 GB を書くため、RAM の
# 多いマシンほど大量のダーティページを抱えたまま最後まで走り、その付けを
# umount -R がまとめて払うことになる。利用者から見ると「アンマウントと
# 表示されてから何分も止まっている」という形で出る。
# 閾値を絶対値で小さく取ると、書き込みが進捗表示のある各ステップの裏で
# 少しずつ進み、最後の待ちがほぼ無くなる。
tune_writeback() {
  # background: この量を超えたら裏で書き出し始める
  sysctl -q -w vm.dirty_background_bytes=67108864  2>/dev/null || true
  # 上限: この量を超えたら書き込み側を待たせる（暴走的な溜め込みを防ぐ）
  sysctl -q -w vm.dirty_bytes=536870912            2>/dev/null || true
  # 古いダーティページを書き出すまでの猶予（既定30秒 → 5秒）
  sysctl -q -w vm.dirty_expire_centisecs=500       2>/dev/null || true
}

_exec_timed() {
  local desc="$1"; shift
  local start_ts=$SECONDS pid rc=0 elapsed
  "$@" >> "${CONFIG[log_file]}" 2>&1 < /dev/null &
  pid=$!
  # 【重要】ポーリング間隔を 1 秒固定にしないこと。
  # run_cmd 系の呼び出しは 170 回以上あり、その大半は 1 秒未満で終わる。
  # 固定 1 秒だと 1 回あたり平均 0.5 秒の取りこぼしが出て、合計で
  # 1分以上の「何もしていない待ち時間」になる。
  # 最初の5秒は細かく見て、長引く処理に入ったら 1 秒間隔へ落として CPU を使わない。
  while kill -0 "$pid" 2>/dev/null; do
    elapsed=$(( SECONDS - start_ts ))
    if [[ "$elapsed" -ge 5 ]]; then
      # EXEC_TIMED_SHOW_DIRTY=yes のときは「あと何 MiB 書き戻せば終わるか」も出す。
      # sync / umount は経過時間だけだと進んでいるのか固まったのか分からず、
      # 実機で「アンマウントと出てから非常に長い」と誤解される原因になっていた。
      if [[ "${EXEC_TIMED_SHOW_DIRTY:-no}" == "yes" ]]; then
        echo -ne "\r  ${CYAN}…${RESET} ${desc}... （$(( elapsed / 60 ))分$(( elapsed % 60 ))秒経過 / 未書き込み $(_dirty_mib) MiB）  "
      else
        echo -ne "\r  ${CYAN}…${RESET} ${desc}... （$(( elapsed / 60 ))分$(( elapsed % 60 ))秒経過）  "
      fi
      sleep 1
    else
      sleep 0.1
    fi
  done
  # 注意: 「if ! wait ...」の形にすると $? が否定後の値（常に0）になるため、
  # 「|| rc=$?」で元の終了コードを取得する（set -e 下でも安全）
  rc=0
  wait "$pid" 2>/dev/null || rc=$?
  return "$rc"
}

run_cmd() {
  # コマンドを実行しログに残す。失敗時はエラー表示して終了
  local desc="$1"; shift
  echo -ne "  ${CYAN}…${RESET} ${desc}..."
  if [[ "${CONFIG[dry_run]}" == "yes" ]]; then
    echo -e "\r  ${YELLOW}⚠${RESET} ${desc} (ドライラン - スキップ)"
    return 0
  fi
  if _exec_timed "$desc" "$@"; then
    echo -e "\r  ${GREEN}✔${RESET} ${desc}                              "
  else
    echo -e "\r  ${RED}✘${RESET} ${desc} — 失敗                              "
    print_err "ログ: ${CONFIG[log_file]}"
    # カーネルの直近エラーもログに追記
    echo "--- dmesg (直近10行) ---" >> "${CONFIG[log_file]}"
    dmesg 2>/dev/null | tail -10 >> "${CONFIG[log_file]}" || true
    exit 1
  fi
}

run_cmd_retry() {
  # ネットワーク系コマンド用: 失敗時に最大3回リトライする
  local desc="$1"; shift
  local max_attempts=3
  local attempt=1
  while [[ "$attempt" -le "$max_attempts" ]]; do
    if [[ "$attempt" -gt 1 ]]; then
      echo -ne "  ${CYAN}…${RESET} ${desc}（リトライ ${attempt}/${max_attempts}）..."
    else
      echo -ne "  ${CYAN}…${RESET} ${desc}..."
    fi
    if [[ "${CONFIG[dry_run]}" == "yes" ]]; then
      echo -e "\r  ${YELLOW}⚠${RESET} ${desc} (ドライラン - スキップ)"
      return 0
    fi
    if _exec_timed "$desc" "$@"; then
      echo -e "\r  ${GREEN}✔${RESET} ${desc}                              "
      return 0
    fi
    echo -e "\r  ${YELLOW}⚠${RESET} ${desc} — 失敗 (試行 ${attempt}/${max_attempts})                              "
    attempt=$(( attempt + 1 ))
    if [[ "$attempt" -le "$max_attempts" ]]; then
      echo -e "  ${YELLOW}…${RESET} 10秒後にリトライします..."
      sleep 10
    fi
  done
  echo -e "  ${RED}✘${RESET} ${desc} — ${max_attempts}回試行しましたが失敗しました"
  print_err "ログ: ${CONFIG[log_file]}"
  exit 1
}

run_cmd_soft() {
  # 失敗してもインストールを継続する（Google Chrome 等の任意処理用）。
  local desc="$1"; shift
  echo -ne "  ${CYAN}…${RESET} ${desc}..."
  if [[ "${CONFIG[dry_run]}" == "yes" ]]; then
    echo -e "\r  ${YELLOW}⚠${RESET} ${desc} (ドライラン - スキップ)"
    return 0
  fi
  if _exec_timed "$desc" "$@"; then
    echo -e "\r  ${GREEN}✔${RESET} ${desc}                              "
    return 0
  fi
  echo -e "\r  ${YELLOW}⚠${RESET} ${desc} — 失敗（スキップして継続）                              "
  print_warn "このパッケージは後から手動で導入できます。ログ: ${CONFIG[log_file]}"
  return 1
}

ask() {
  local prompt="$1"
  local default="${2:-}"
  local answer
  local tty_out tty_in; _resolve_tty tty_out tty_in
  if [[ -n "$default" ]]; then
    echo -ne "  ${BOLD}${prompt}${RESET} [${default}]: " > "$tty_out"
  else
    echo -ne "  ${BOLD}${prompt}${RESET}: " > "$tty_out"
  fi
  _read_input answer "$tty_in" "$tty_out"
  echo "${answer:-$default}"
}

ask_password() {
  local prompt="$1"
  local pw1 pw2
  local tty_out tty_in; _resolve_tty tty_out tty_in
  while true; do
    echo -ne "  ${BOLD}${prompt}${RESET}: " > "$tty_out"
    _read_input pw1 "$tty_in" "$tty_out" silent; echo > "$tty_out"
    if [[ "$pw1" == *"|"* ]]; then
      echo -e "  ${RED}✘${RESET} パスワードに '|' は使用できません。" > "$tty_out"
      continue
    fi
    echo -ne "  ${BOLD}（確認）${prompt}${RESET}: " > "$tty_out"
    _read_input pw2 "$tty_in" "$tty_out" silent; echo > "$tty_out"
    if [[ "$pw1" == "$pw2" ]]; then
      echo "$pw1"
      return
    fi
    echo -e "  ${RED}✘${RESET} パスワードが一致しません。もう一度入力してください。" > "$tty_out"
  done
}

confirm() {
  local prompt="${1:-続けますか？}"
  local answer
  local tty_out tty_in; _resolve_tty tty_out tty_in
  while true; do
    echo -ne "  ${BOLD}${prompt}${RESET} [y/N]: " > "$tty_out"
    _read_input answer "$tty_in" "$tty_out"
    case "$answer" in
      [yY]) return 0 ;;
      [nN]|"") return 1 ;;
      *) echo -e "  ${RED}✘${RESET} y または n を入力してください。" > "$tty_out" ;;
    esac
  done
}

# confirm の既定 Yes 版（Enter で承認）。日本語環境の推奨項目に使う。
confirm_yes() {
  local prompt="${1:-続けますか？}"
  local answer
  local tty_out tty_in; _resolve_tty tty_out tty_in
  while true; do
    echo -ne "  ${BOLD}${prompt}${RESET} ${GREEN}[Y/n]${RESET}: " > "$tty_out"
    _read_input answer "$tty_in" "$tty_out"
    case "$answer" in
      [yY]|"") return 0 ;;
      [nN]) return 1 ;;
      *) echo -e "  ${RED}✘${RESET} y または n を入力してください。" > "$tty_out" ;;
    esac
  done
}

# coffee版: 呼び出し前に SELECT_DEFAULT（1始まりの番号）をセットしておくと、
# その番号を「coffee版のデフォルト」として表示し、Enter だけで選べるようになる。
# 呼び出し後は必ずクリアするので、セットしなかった他の呼び出しには影響しない。
select_from_list() {
  # $() サブシェルで呼ばれても表示されるよう /dev/tty に直接出力する
  local prompt="$1"
  shift
  local options=("$@")
  local tty_out tty_in; _resolve_tty tty_out tty_in
  local default="${SELECT_DEFAULT:-}"
  unset SELECT_DEFAULT

  echo -e "  ${BOLD}${prompt}${RESET}" > "$tty_out"
  for i in "${!options[@]}"; do
    if [[ -n "$default" && "$((i+1))" == "$default" ]]; then
      printf "    ${CYAN}%2d)${RESET} %s ${YELLOW}← 既定（Enter でこのまま）${RESET}\n" "$((i+1))" "${options[$i]}" > "$tty_out"
    else
      printf "    ${CYAN}%2d)${RESET} %s\n" "$((i+1))" "${options[$i]}" > "$tty_out"
    fi
  done
  local choice max
  max="${#options[@]}"
  while true; do
    if [[ -n "$default" ]]; then
      echo -ne "  番号を入力 [Enter=${default}]: " > "$tty_out"
    else
      echo -ne "  番号を入力: " > "$tty_out"
    fi
    _read_input choice "$tty_in" "$tty_out"
    [[ -z "$choice" && -n "$default" ]] && choice="$default"
    if [[ "$choice" =~ ^[0-9]+$ ]] && [[ "$choice" -ge 1 ]] && [[ "$choice" -le "$max" ]]; then
      echo "${options[$((choice-1))]}"
      return
    fi
    echo -e "  ${RED}✘${RESET} 1〜${max} の番号を入力してください。" > "$tty_out"
  done
}

# CONFIG[users] を行ごとにパースして変数に展開するヘルパー
# 使い方: parse_users_line "$entry"  → uname/upw/usudo/ushell/ugroups をセット
# chroot 内のユーザーにパスワードを設定する（特殊文字対応・tmpfile 経由）
_set_password() {
  local user="$1"
  local pw="$2"
  if [[ "${CONFIG[dry_run]}" == "yes" ]]; then
    print_warn "_set_password: ${user} (ドライラン - スキップ)"
    return 0
  fi
  local tmpfile rc=0
  tmpfile=$(mktemp)
  chmod 600 "$tmpfile"
  printf "%s:%s" "$user" "$pw" > "$tmpfile"
  # 【重要】chpasswd が失敗すると set -e でここから先に進まないため、
  # 素直に書くと rm -f に到達せず平文パスワードのファイルが /tmp に残る。
  # 「|| rc=$?」で失敗を受け止め、必ず消してから改めて失敗を伝える。
  arch-chroot /mnt chpasswd < "$tmpfile" || rc=$?
  rm -f "$tmpfile"
  if [[ "$rc" -ne 0 ]]; then
    print_err "${user} のパスワード設定に失敗しました（終了コード ${rc}）"
    return "$rc"
  fi
}

parse_users_line() {
  local entry="$1"
  uname=$(cut -d'|' -f1  <<< "$entry")
  upw=$(cut -d'|' -f2    <<< "$entry")
  usudo=$(cut -d'|' -f3  <<< "$entry")
  ushell=$(cut -d'|' -f4 <<< "$entry")
  ugroups=$(cut -d'|' -f5 <<< "$entry")
}

# pacman.conf を最適化する（Color有効化・並列DL・multilib有効化）
# 引数: 対象ファイルのパス（例: /etc/pacman.conf または /mnt/etc/pacman.conf）
tune_pacman_conf() {
  local conf="$1"
  [[ -f "$conf" ]] || return 0
  sed -i 's/^#Color$/Color/'                                                        "$conf"
  sed -i 's/^#ParallelDownloads.*/ParallelDownloads = 10/'                           "$conf"
  sed -i '/^#\[multilib\]/,/^#Include = \/etc\/pacman.d\/mirrorlist/s/^#//'        "$conf"
}

# ============================================
# ステップ 1: ディスク選択
# ============================================

# 選択したディスクに Windows がありそうかを調べ、CONFIG[windows_found] に記録する。
#
# 【経緯】ここはかつて「Windows とデュアルブートしますか？」という設問だった。
# ところがこの設問は名前が約束しすぎていた。「デュアルブート」と言われれば
# 両方から起動できるよう取り計らってくれると読めるが、実際にはパーティションを
# 一切守らない。そのため直後に十数行かけて「守られません」と打ち消す羽目になり、
# 設問そのものが分かりにくくなっていた。
#
# 決めたいのは「RTC を localtime にするか」「os-prober を入れるか」だが、
# それは利用者に聞くことではなく、ディスクに Windows があるかどうかから
# 決まる話でしかない。しかも本人の申告より実際のディスクのほうが確実で、
# 「Windows があるのに『いいえ』と答えて時刻がずれる」事故も防げる。
# よって設問を廃止し、ここで判定する。
#
# 判定は NTFS パーティションの有無で行う。Windows の C: は NTFS なので、
# 実用上これで足りる。回復パーティションだけが残った状態でも NTFS は
# 見えるが、その場合に localtime と os-prober が入っても実害は無い。
_detect_windows_on_disk() {
  CONFIG[windows_found]="no"
  [[ -b "${CONFIG[disk]}" ]] || return 0
  command -v lsblk > /dev/null 2>&1 || return 0

  if lsblk -rno FSTYPE "${CONFIG[disk]}" 2>/dev/null | grep -qix "ntfs"; then
    CONFIG[windows_found]="yes"
  fi
}

step_disk() {
  print_step "ディスク選択"

  # Arch ISO が載っているデバイスを特定して除外
  local iso_dev=""
  iso_dev=$(findmnt -n -o SOURCE /run/archiso/bootmnt 2>/dev/null || \
            findmnt -n -o SOURCE /run/miso 2>/dev/null || true)
  # パーティション番号を除いてデバイス名だけ取り出す（例: /dev/sda1 → sda）
  if [[ -n "$iso_dev" ]]; then
    local iso_dev_name="${iso_dev#/dev/}"
    if [[ -d "/sys/class/block/${iso_dev_name}" ]]; then
      # sysfs から親デバイス名（PKNAME 相当）を取得
      if [[ -f "/sys/class/block/${iso_dev_name}/partition" ]]; then
        iso_dev=$(basename "$(readlink -f "/sys/class/block/${iso_dev_name}/..")" 2>/dev/null || echo "$iso_dev_name")
      else
        iso_dev="$iso_dev_name"
      fi
    else
      iso_dev=$(echo "$iso_dev" | sed 's|/dev/||; s|[0-9]*$||; s|p[0-9]*$||')
    fi
  fi

  # ディスク一覧を構築（sysfs から直接読み取り、loop・光学・ISO デバイスを除外）
  local disks=()
  for devpath in /sys/block/*; do
    [[ -e "$devpath" ]] || continue
    local devname
    devname=$(basename "$devpath")

    # loop, ram, sr, zram デバイスを除外
    [[ "$devname" =~ ^(loop|ram|sr|zram) ]] && continue

    # サイズが 0（または読み取れない）デバイスを除外
    local sectors
    sectors=$(cat "$devpath/size" 2>/dev/null || echo 0)
    # (( sectors == 0 )) は set -e で終了するため [[ ]] で比較
    [[ "$sectors" -eq 0 ]] && continue

    # ISO デバイスをスキップ
    [[ -n "$iso_dev" && "$devname" == "$iso_dev" ]] && continue

    # サイズを人間が読みやすい形式に変換
    local bytes
    bytes=$(( sectors * 512 ))
    local size_str
    # (( bytes >= N )) は false のとき終了コード1 → set -e で終了するため if で保護
    if [[ "$bytes" -ge 1099511627776 ]]; then
      size_str="$(( bytes / 1099511627776 ))T"
    elif [[ "$bytes" -ge 1073741824 ]]; then
      size_str="$(( bytes / 1073741824 ))G"
    elif [[ "$bytes" -ge 1048576 ]]; then
      size_str="$(( bytes / 1048576 ))M"
    else
      size_str="${bytes}B"
    fi

    # モデル名を取得
    local model=""
    if [[ -f "$devpath/device/model" ]]; then
      model=$(tr -d '\r\n' < "$devpath/device/model" | xargs)
    elif [[ -f "$devpath/device/name" ]]; then
      model=$(tr -d '\r\n' < "$devpath/device/name" | xargs)
    fi

    # 接続タイプを sysfs パスから判定
    local sys_link
    sys_link=$(readlink -f "$devpath" 2>/dev/null || echo "")
    local label=""
    if [[ "$sys_link" == *"/usb"* ]]; then
      label=" [外付け USB]"
    elif [[ "$sys_link" == *"/nvme"* ]]; then
      label=" [NVMe]"
    elif [[ "$sys_link" == *"/ata"* ]]; then
      label=" [SATA]"
    fi

    disks+=("/dev/${devname} (${size_str}) ${model}${label}")
  done

  if [[ ${#disks[@]} -eq 0 ]]; then
    print_err "インストール先ディスクが見つかりません。"
    echo -e "\n${YELLOW}─── デバッグ・診断情報 ───${RESET}"
    echo "除外対象 (iso_dev)  : ${iso_dev:-なし}"
    echo "利用可能な /sys/block デバイス一覧:"
    ls /sys/block || true
    echo -e "─────────────────────────\n"
    exit 1
  fi

  # ISO デバイスを除外した旨を表示
  if [[ -n "$iso_dev" ]]; then
    print_ok "Arch ISO デバイス (/dev/${iso_dev}) を候補から除外しました"
  fi

  echo ""
  # ディスク一覧を直接表示して番号選択（配列要素にスペースが含まれるため select_from_list は使わない）
  echo -e "  ${BOLD}インストール先ディスクを選択してください:${RESET}"
  for i in "${!disks[@]}"; do
    printf "    ${CYAN}%2d)${RESET} %s\n" "$((i+1))" "${disks[$i]}"
  done
  local choice max
  local tty_out tty_in; _resolve_tty tty_out tty_in
  max="${#disks[@]}"
  while true; do
    echo -ne "  番号を入力: "
    _read_input choice "$tty_in" "$tty_out"
    if [[ "$choice" =~ ^[0-9]+$ ]] && [[ "$choice" -ge 1 ]] && [[ "$choice" -le "$max" ]]; then
      break
    fi
    print_err "1〜${max} の番号を入力してください。"
  done
  local selected="${disks[$((choice-1))]}"
  CONFIG[disk]=$(echo "$selected" | awk '{print $1}')

  # 外付けディスクかどうかを記録（完了メッセージで案内するため）
  local disk_name="${CONFIG[disk]#/dev/}"
  local disk_sys_link
  disk_sys_link=$(readlink -f "/sys/block/${disk_name}" 2>/dev/null || echo "")
  if [[ "$disk_sys_link" == *"/usb"* ]]; then
    CONFIG[disk_is_external]="yes"
    print_warn "外付け USB デバイスが選択されました"
  else
    CONFIG[disk_is_external]="no"
  fi

  print_warn "選択: ${CONFIG[disk]}"
  print_warn "このディスクの全データが消去されます！"

  if ! confirm "本当によろしいですか？"; then
    print_err "中断しました。"
    exit 1
  fi
  print_ok "ディスク: ${CONFIG[disk]}"

  # 【重要】検出はディスク確定のたびに行うこと。修正メニューから
  # ディスクを選び直したときに、前のディスクの判定が残ってはいけない。
  _detect_windows_on_disk
  if [[ "${CONFIG[windows_found]}" == "yes" ]]; then
    print_warn "このディスクに Windows（NTFS）が見つかりました。"
    echo "      ハードウェアクロックを Windows に合わせ、起動メニューにも"
    echo "      Windows を表示する設定にします（時刻ずれを防ぐため）。"
    echo ""
    echo "      ただし Windows を残すには、次の「パーティション構成」で"
    echo "      必ず「手動（fdisk）」を選び、空き領域に作成してください。"
    echo "      「自動」を選ぶとディスク全体が消去され、Windows も消えます。"
  fi
}

# ============================================
# ステップ 2: パーティション構成
# ============================================

step_partition_scheme() {
  print_step "パーティション構成"

  # BIOS 環境でも本スクリプトは GPT を使用する（GRUB は BIOS+GPT に対応）
  if [[ "${CONFIG[boot_mode]}" == "bios" ]]; then
    print_warn "BIOS 環境では GPT + BIOS Boot パーティション(1MB) を使用します。"
    print_warn "MBR/DOS 形式を希望する場合は「手動（fdisk）」を選択してください。"
    echo ""
  fi

  local scheme
  scheme=$(select_from_list "パーティション構成を選択:" \
    "自動（推奨） - EFI 512M + / のみ（swap なし・zram 推奨）" \
    "自動 - EFI 512M + swap (RAM同容量) + /（ハイバネート使用時）" \
    "手動（fdisk を起動）")

  case "$scheme" in
    "自動（推奨） - EFI 512M + / のみ（swap なし・zram 推奨）") CONFIG[partition_scheme]="auto_noswap" ;;
    "自動 - EFI 512M + swap (RAM同容量) + /（ハイバネート使用時）") CONFIG[partition_scheme]="auto_swap" ;;
    "手動（fdisk を起動）")                                        CONFIG[partition_scheme]="manual" ;;
  esac
  print_ok "パーティション構成: ${CONFIG[partition_scheme]}"

  # ファイルシステム選択（手動時はユーザーが自分でフォーマットするため省略）
  if [[ "${CONFIG[partition_scheme]}" != "manual" ]]; then
    echo ""
    echo -e "  ${YELLOW}ヒント: Enter で xfs（coffee 版の既定）。迷ったら ext4 も安全な選択です。${RESET}"
    local fs
    # coffee版: xfs をデフォルトにする。select_from_list はサブシェルで動くため、
    # SELECT_DEFAULT はこのコマンドだけに前置きし、呼び出し元のシェルには残さない。
    fs=$(SELECT_DEFAULT=3 select_from_list "ルートパーティションのファイルシステムを選択:" \
      "ext4   - 安定・実績豊富・推奨（初心者向け）" \
      "btrfs  - スナップショット対応・モダン（中〜上級者向け）" \
      "xfs    - 大容量・高性能（サーバー・上級者向け）")
    case "$fs" in
      "ext4   - 安定・実績豊富・推奨（初心者向け）") CONFIG[fs_type]="ext4" ;;
      "btrfs  - スナップショット対応・モダン（中〜上級者向け）") CONFIG[fs_type]="btrfs" ;;
      "xfs    - 大容量・高性能（サーバー・上級者向け）")         CONFIG[fs_type]="xfs" ;;
    esac
    print_ok "ファイルシステム: ${CONFIG[fs_type]}"
  fi
}

# ============================================
# ステップ 3: システム設定
# ============================================

step_system() {
  print_step "システム設定"

  # --- 日本語環境専用: ロケール・タイムゾーンは固定 ---
  CONFIG[locale]="ja_JP.UTF-8"
  CONFIG[timezone]="Asia/Tokyo"
  CONFIG[japanese_env]="yes"
  print_ok "ロケール    : ja_JP.UTF-8（日本語環境専用）"
  print_ok "タイムゾーン: Asia/Tokyo"

  # --- キーボード配列: 日本語特化のため jp106 固定 ---
  # （US 配列キーボードを使う場合はインストール後に
  #   localectl set-keymap us / set-x11-keymap us で変更可能）
  CONFIG[keymap]="jp106"
  print_ok "キーマップ  : jp106（日本語 JIS 固定）"

  # --- 日本語入力 (IME): 日本語特化のため fcitx5 + Mozc 固定 ---
  CONFIG[jp_ime]="fcitx5-mozc"
  print_ok "IME         : fcitx5-mozc（固定）"

  # --- ホスト名 ---
  # 英数字とハイフンのみ許可（RFC 1123 準拠・63文字以内）。
  # 未検証のまま bash -c に埋め込むと ' などでコマンドが壊れるため必ず検証する。
  echo ""
  while true; do
    CONFIG[hostname]=$(ask "ホスト名" "archlinux")
    if [[ -z "${CONFIG[hostname]}" ]]; then
      print_err "ホスト名は必須です。"
      continue
    fi
    if [[ ! "${CONFIG[hostname]}" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$ ]]; then
      print_err "ホスト名は英数字とハイフンのみ・63文字以内です（先頭/末尾にハイフン不可）。"
      continue
    fi
    break
  done
  print_ok "ホスト名: ${CONFIG[hostname]}"

  # --- GPU ドライバーの選択 ---
  echo ""

  # GPU を自動検出して推奨を提示
  #
  # 【重要】lspci の全行ではなく、表示デバイスの行（VGA / 3D / Display）だけを見ること。
  # また AMD / ATI は大文字小文字を区別した単語として照合すること。
  # かつて全行に対して grep -qi "AMD\|ATI\|Radeon" をかけていたため、
  # Intel 機のホストブリッジ行「Intel Corporation」の "Corpor-ati-on" に一致し、
  # Intel HD 620 の実機が AMD と誤判定されていた（amdgpu 用パッケージが入り、
  # vulkan-intel が入らない）。自動採用で確認も出ないため、気付きにくい。
  local detected_gpu=""
  local recommended=""
  local gpu_lines=""
  gpu_lines=$(lspci 2>/dev/null | grep -E 'VGA compatible controller|3D controller|Display controller' || true)
  if grep -qiw "NVIDIA" <<< "$gpu_lines"; then
    detected_gpu="NVIDIA"
    recommended="nvidia"
  elif grep -qE '\b(AMD|ATI)\b|Radeon' <<< "$gpu_lines"; then
    detected_gpu="AMD"
    recommended="amdgpu"
  elif grep -qiw "Intel" <<< "$gpu_lines"; then
    detected_gpu="Intel"
    recommended="intel"
  elif systemd-detect-virt 2>/dev/null | grep -qiE "oracle|kvm|vmware|qemu"; then
    detected_gpu="仮想環境"
    recommended="virtual"
  fi

  if [[ -n "$detected_gpu" ]]; then
    # 検出に成功した場合は確認せず自動採用する
    # （検出失敗時のみ下の手動選択にフォールバック）
    CONFIG[gpu_driver]="$recommended"
    print_ok "検出された GPU: ${detected_gpu} → ドライバー ${CONFIG[gpu_driver]} を自動選択"
    return
  fi

  print_warn "GPU を自動検出できませんでした。手動で選択してください。"
  echo ""

  # 手動選択（自動検出できなかった場合、またはユーザーが手動選択を希望した場合）
  echo -e "  ${YELLOW}ヒント: 自分の PC の GPU メーカーが分からない場合は${RESET}"
  echo -e "  ${YELLOW}「インストールしない」を選ぶと基本的な画面表示は動作します。${RESET}"
  echo ""

  local gpu
  gpu=$(select_from_list "GPU ドライバーを選択してください:" \
    "NVIDIA    - NVIDIA 製 GPU（GeForce など）※ゲーミング PC に多い" \
    "NVIDIA    - NVIDIA 製 GPU（オープンソース版 Nouveau）" \
    "AMD       - AMD 製 GPU（Radeon など）" \
    "Intel     - Intel 内蔵グラフィックス（CPU 内蔵グラフィック）" \
    "仮想環境  - VirtualBox・VMware 上で動かしている場合" \
    "インストールしない - よく分からない場合・後で手動設定")

  case "$gpu" in
    "NVIDIA    - NVIDIA 製 GPU（GeForce など）※ゲーミング PC に多い") CONFIG[gpu_driver]="nvidia" ;;
    "NVIDIA    - NVIDIA 製 GPU（オープンソース版 Nouveau）")            CONFIG[gpu_driver]="nouveau" ;;
    "AMD       - AMD 製 GPU（Radeon など）")                            CONFIG[gpu_driver]="amdgpu" ;;
    "Intel     - Intel 内蔵グラフィックス（CPU 内蔵グラフィック）")     CONFIG[gpu_driver]="intel" ;;
    "仮想環境  - VirtualBox・VMware 上で動かしている場合")              CONFIG[gpu_driver]="virtual" ;;
    *)                                                                   CONFIG[gpu_driver]="none" ;;
  esac
  print_ok "GPU ドライバー: ${CONFIG[gpu_driver]}"
}

# ============================================
# ステップ 4: ユーザー設定
# ============================================

step_users() {
  print_step "ユーザー設定"

  # --- root パスワード ---
  echo -e "  ${YELLOW}root パスワードを設定します${RESET}"
  local root_pw
  while true; do
    root_pw=$(ask_password "root パスワード")
    if [[ ${#root_pw} -lt 8 ]]; then
      print_err "パスワードは8文字以上にしてください。"
      continue
    fi
    break
  done
  CONFIG[root_password]="$root_pw"
  print_ok "root パスワード設定済み"

  # --- 一般ユーザー（複数対応） ---
  CONFIG[users]=""          # "user1:pw1:sudo:bash user2:pw2:nosudo:zsh" 形式で蓄積
  CONFIG[users_count]=0

  # 【重要】一般ユーザーは最低1人必須。
  # coffee 版は COSMIC + SDDM 固定で、SDDM は root を一覧に出さず、
  # root でのデスクトップログインも想定していない。以前は 0 人のまま進めたため、
  # インストールは成功するのにログイン画面から誰も入れない状態になりえた。
  # AUR ビルド（makepkg は root 不可）も一般ユーザーが前提になっている。
  while true; do
    echo ""
    if [[ "${CONFIG[users_count]}" -eq 0 ]]; then
      echo -e "  ${YELLOW}ログイン用の一般ユーザーを作成します（1人以上必須）${RESET}"
    else
      confirm "さらにユーザーを追加しますか？" || break
    fi

    # ユーザー名
    local uname
    while true; do
      uname=$(ask "ユーザー名")
      if [[ -z "$uname" ]]; then
        print_err "ユーザー名は必須です。"
        continue
      fi
      if [[ ! "$uname" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
        print_err "小文字英数字・アンダースコア・ハイフンのみ使用できます（先頭は英字）。"
        continue
      fi
      # 重複チェック
      if [[ -n "${CONFIG[users]}" ]] && echo "${CONFIG[users]}" | grep -q "^${uname}|"; then
        print_err "そのユーザー名はすでに追加されています。"
        continue
      fi
      break
    done

    # パスワード
    local upw
    while true; do
      upw=$(ask_password "${uname} のパスワード")
      if [[ ${#upw} -lt 8 ]]; then
        print_err "パスワードは8文字以上にしてください。"
        continue
      fi
      break
    done

    # sudo 権限
    local usudo="no"
    if confirm "${uname} に sudo（管理者権限）を付与しますか？"; then
      local sudo_type
      sudo_type=$(select_from_list "sudo の種類:" \
        "通常 sudo（実行時にパスワードを求める・推奨）" \
        "NOPASSWD（パスワードなしで sudo 実行）")
      case "$sudo_type" in
        "通常 sudo（実行時にパスワードを求める・推奨）") usudo="yes" ;;
        "NOPASSWD（パスワードなしで sudo 実行）")        usudo="nopasswd" ;;
      esac
    fi

    # ログインシェル
    local ushell
    ushell=$(select_from_list "${uname} のログインシェル:" \
      "bash  - デフォルト・安定" \
      "zsh   - 高機能・補完が強力" \
      "fish  - ユーザーフレンドリー・シンタックスハイライト")
    case "$ushell" in
      "bash  - デフォルト・安定")                       ushell="bash" ;;
      "zsh   - 高機能・補完が強力")                     ushell="zsh" ;;
      "fish  - ユーザーフレンドリー・シンタックスハイライト") ushell="fish" ;;
    esac

    # 追加グループ
    local ugroups="wheel,audio,video,storage,optical,input"

    # リストに追記（区切り文字は | ）
    local entry="${uname}|${upw}|${usudo}|${ushell}|${ugroups}"
    if [[ -z "${CONFIG[users]}" ]]; then
      CONFIG[users]="$entry"
    else
      CONFIG[users]="${CONFIG[users]}
${entry}"
    fi
    CONFIG[users_count]=$(( CONFIG[users_count] + 1 ))

    # 追加のたびに確認表示を出す。
    # 【注意】以前は users_count -eq 1 のときだけ表示していたため、
    # 2人目以降は入力し終えても何も反応が返らず「追加されたのか分からない」状態だった。
    print_ok "ユーザー追加: ${uname} (sudo: ${usudo}, shell: ${ushell})"
  done

  # ユーザー一覧を表示
  if [[ "${CONFIG[users_count]}" -gt 0 ]]; then
    echo ""
    print_ok "作成予定ユーザー一覧:"
    while IFS= read -r entry; do
      [[ -z "$entry" ]] && continue
      parse_users_line "$entry"
      echo -e "    ${CYAN}•${RESET} ${uname}  sudo: ${usudo}  shell: ${ushell}"
    done <<< "${CONFIG[users]}"
  fi
}


# ============================================
# ステップ 5: ブートローダー
# ============================================

detect_boot_mode() {
  if [[ -d /sys/firmware/efi/efivars ]]; then
    echo "uefi"
  else
    echo "bios"
  fi
}

step_bootloader() {
  print_step "ブートローダー"

  local boot_mode="${CONFIG[boot_mode]}"

  if [[ "$boot_mode" == "uefi" ]]; then
    print_ok "ファームウェア: UEFI 検出"

    local bl
    # coffee版: systemd-boot が既定（UEFI ならこれで足りる）
    bl=$(SELECT_DEFAULT=1 select_from_list "ブートローダーを選択:" \
      "systemd-boot（推奨・シンプル・追加パッケージ不要）" \
      "GRUB（マルチブートや特殊構成向け）")

    case "$bl" in
      "systemd-boot（推奨・シンプル・追加パッケージ不要）") CONFIG[bootloader]="systemd-boot" ;;
      "GRUB（マルチブートや特殊構成向け）")                  CONFIG[bootloader]="grub" ;;
    esac
  else
    print_warn "ファームウェア: BIOS（レガシー）検出"
    print_warn "systemd-boot は UEFI 専用のため、GRUB を使用します。"
    CONFIG[bootloader]="grub"
  fi

  print_ok "ブートローダー: ${CONFIG[bootloader]}"
}

# ステップ: デスクトップ環境
# ============================================
# coffee 版は COSMIC + SDDM の一本構成。
#
# 【経緯】元は 8 種のデスクトップ環境と 5 種のログイン画面を選べたが、
# 組み合わせが多すぎて検証が追いつかず、大半は一度も実行されない
# まま「動くはず」のコードとして残っていた。動かないコードは直せない。
# 実際に使う構成だけに絞り、そのぶん COSMIC まわりを厚く見る方針に変えた。
# 他の環境が必要なら、汎用版の install.sh を使うこと。
step_desktop() {
  print_step "デスクトップ環境"

  CONFIG[desktop]="cosmic"
  CONFIG[dm]="sddm"

  print_ok "デスクトップ: COSMIC"
  print_ok "ログイン画面: SDDM"
}

# ============================================
# ステップ: 設定の引き継ぎ元（ホストPC / GitHub / なし）
# ============================================

# 指定ディレクトリ配下の .config から、引き継ぎ対象になる設定を列挙して表示する。
# step_config_source のホスト側/GitHub側の2箇所で使う。
# 引き継ぎ対象として「実際にコピーされるもの」だけを列挙する。
#
# 【重要】この一覧は do_desktop 側の app_configs / file_configs と必ず揃えること。
# 表示だけ広げても実態は変わらず、「引き継ぐと出たのに引き継がれない」という
# 食い違いになるだけなので、実際にコピーするものと同じ条件を保つ。
#
# cosmic: パネル/ドック配置・テーマ・固定アプリ・既定ターミナル (ghostty) は
#         ~/.config/cosmic 配下にまとめて入っているため一括で表示する
#         （壁紙関連とディスプレイ構成だけは do_desktop 側で個別に除外する）。
_inheritable_config_list() {
  local list=(mpv cosmic)
  # 日本語入力は DE に依存しない。mozc のユーザー辞書と学習履歴が入っており、
  # ここを引き継げるかどうかが変換の使い勝手を大きく左右する。
  if [[ "${CONFIG[japanese_env]}" == "yes" && "${CONFIG[jp_ime]:-none}" =~ ^fcitx5 ]]; then
    list+=(fcitx5 mozc)
  fi
  printf '%s\n' "${list[@]}"
}

_print_inheritable_configs() {
  local dir="$1"
  local found=() c
  while IFS= read -r c; do
    [[ -e "${dir}/.config/${c}" ]] && found+=("$c")
  done < <(_inheritable_config_list)
  # starship.toml はディレクトリではなく単体ファイルなので個別に見る。
  [[ -e "${dir}/.config/starship.toml" ]] && found+=("starship")
  if [[ "${#found[@]}" -gt 0 ]]; then
    echo -e "    ${GRAY}引き継ぎ対象: ${found[*]}${RESET}"
  else
    echo -e "    ${GRAY}引き継ぎ対象になる設定は見つかりませんでした${RESET}"
  fi
}

step_config_source() {
  print_step "設定の引き継ぎ"

  # 何が利用可能かを先に調べて提示する。
  # 【重要】_host_home ではなく _host_home_raw を使うこと。
  # _host_home は CONFIG[config_source] を見て分岐するため、
  # 再実行（修正ループ）時に前回の選択が検出結果に混ざってしまう。
  local host_dir
  host_dir=$(_host_home_raw)

  # 引き継ぎ対象は _inheritable_config_list と揃えること。
  # 挙げたのに引き継がれない項目があると、利用者に無い機能を期待させてしまう。
  echo -e "  ${GRAY}COSMIC のパネル/ドック配置・テーマ・固定アプリ・既定ターミナル(ghostty)や"
  echo -e "  日本語入力（変換履歴・ユーザー辞書）、mpv などの設定を"
  echo -e "  新しい環境へ引き継ぐかどうかを選べます。${RESET}"
  echo -e "  ${GRAY}※ 壁紙・SDDMログイン画面の背景だけは、この選択に関係なく"
  echo -e "     常に ${THEME_LABEL} のものになります。${RESET}"
  echo ""

  if [[ -n "$host_dir" ]]; then
    print_ok "ホストPCの設定を検出: ${host_dir}"
    # 何が引き継がれるのか具体的に見せる（想像で選ばせない）
    _print_inheritable_configs "$host_dir"
  else
    print_warn "ホストPCの設定は見つかりませんでした（素の Live ISO から起動した場合など）"
  fi
  echo -e "  ${GRAY}GitHub リポジトリ: ${ESCA_DOTFILES_REPO} (${ESCA_DOTFILES_BRANCH})${RESET}"
  echo -e "  ${GRAY}※ 壁紙とSDDMログイン画面の背景は、ここでの選択に関係なく"
  echo -e "     常に別途 GitHub から取得を試みます（この選択はアプリ設定のみが対象）。${RESET}"
  echo ""

  # 選択肢は「実際に選べるもの」だけを出す。
  # 使えない選択肢を並べて選ばせてから失敗させるのは不親切なため。
  # ただし GitHub からの取得は事前確認にネットワーク待ちが要るので、
  # 常に選択肢として出しておき、選ばれた時点で取得して結果を知らせる。
  local opts=()
  [[ -n "$host_dir" ]] && opts+=("ホストPCの設定を引き継ぐ  - 今の見た目・操作感をそのまま再現（推奨）")
  opts+=("GitHub から取得する        - ${ESCA_DOTFILES_REPO##*/} の最新設定を使う")
  opts+=("引き継がない              - 各パッケージの既定設定のみ（素の状態）")

  # coffee版: ホストPCの設定が検出できた場合のみ、それを既定にする
  # （ホストPCの設定が見つかった場合、opts[0] は必ず「ホストPCの設定を引き継ぐ」になる）。
  local sel
  if [[ -n "$host_dir" ]]; then
    sel=$(SELECT_DEFAULT=1 select_from_list "設定の引き継ぎ元を選択:" "${opts[@]}")
  else
    sel=$(select_from_list "設定の引き継ぎ元を選択:" "${opts[@]}")
  fi
  case "$sel" in
    "ホストPCの設定を引き継ぐ"*) CONFIG[config_source]="host" ;;
    "GitHub から取得する"*)      CONFIG[config_source]="git" ;;
    *)                            CONFIG[config_source]="none" ;;
  esac

  # GitHub を選んだ場合はこの場で取得まで済ませる。
  # インストール本番（do_desktop）まで失敗が分からないと、
  # 「設定が入らなかった理由」が分かりにくくなるため。
  if [[ "${CONFIG[config_source]}" == "git" ]]; then
    echo -ne "  ${CYAN}…${RESET} GitHub から dotfiles を取得中..."
    local git_dir
    git_dir=$(_git_dotfiles)
    if [[ -n "$git_dir" ]]; then
      echo -e "\r  ${GREEN}✔${RESET} GitHub から dotfiles を取得しました      "
      _print_inheritable_configs "$git_dir"
    else
      echo -e "\r  ${YELLOW}⚠${RESET} GitHub から dotfiles を取得できませんでした"
      print_warn "引き継ぎなし（既定設定のみ）に切り替えます。ネットワークまたはリポジトリURLを確認してください。"
      CONFIG[config_source]="none"
    fi
  fi

  case "${CONFIG[config_source]}" in
    host)    print_ok "設定の引き継ぎ: ホストPC (${host_dir})" ;;
    git)     print_ok "設定の引き継ぎ: GitHub (${ESCA_DOTFILES_REPO})" ;;
    none)    print_ok "設定の引き継ぎ: なし（既定設定のみ）" ;;
  esac
}

# ============================================
# ステップ: フォント選択
# ============================================

step_fonts() {
  print_step "フォント設定"

  # 日本語環境専用: 日本語表示に必須のフォントを自動インストール
  local pkgs=(noto-fonts noto-fonts-cjk noto-fonts-emoji)
  print_ok "日本語フォントを自動インストール:"
  echo -e "    ${GRAY}• noto-fonts（欧文）/ noto-fonts-cjk（日本語）/ noto-fonts-emoji（絵文字）${RESET}"

  # 高品質フォント（Adobe 源ノ）: 日本語特化のため固定で導入
  pkgs+=(adobe-source-han-sans-jp-fonts adobe-source-han-serif-jp-fonts)
  print_ok "源ノ角ゴシック + 源ノ明朝 を追加（固定）"

  # プログラミング向け等幅フォント: 軽量のため固定で導入
  pkgs+=(ttf-fira-code)
  print_ok "ttf-fira-code を追加（固定）"

  CONFIG[font_pkgs]="${pkgs[*]}"
  CONFIG[font_setup_fontconfig]="yes"
  echo ""
  print_ok "インストール予定フォント: ${CONFIG[font_pkgs]}"
  print_ok "fontconfig: 日本語・絵文字の優先度を自動設定します"
}

# ============================================
# ステップ 7: 追加パッケージ
# ============================================

step_extra_packages() {
  print_step "追加パッケージ・サービス"

  echo -e "  日本語環境向けの推奨設定です。${GREEN}Enter でそのまま有効化${RESET}できます。\n"

  # zram（圧縮RAMスワップ）: 推奨のため固定で有効化
  CONFIG[extra_zram]="yes"
  print_ok "zram         : 有効（固定・RAM 上の圧縮スワップ）"

  # fstrim.timer（SSD の定期 TRIM）: 固定で有効化
  # （HDD 環境では単に何もしないだけで害はない）
  CONFIG[extra_fstrim]="yes"
  print_ok "fstrim.timer : 有効（固定・SSD の定期 TRIM）"
  echo ""

  # OpenSSH サーバー（セキュリティに関わるため質問を残す）
  # coffee版: 既定は No（使わない人にはリモートからの入口を開けない）
  if confirm "OpenSSH サーバーをインストール・有効化しますか？（リモート接続用）"; then
    CONFIG[extra_ssh]="yes"; print_ok "OpenSSH を有効化（sshd を自動起動）"
  else
    CONFIG[extra_ssh]="no"; print_ok "OpenSSH はスキップ"
  fi

  # LibreOffice（デスクトップ環境選択時のみ）
  # 依存込みで 1GB 近くあるため、ミニマル構成を望むユーザー向けに選択制にする
  if [[ "${CONFIG[desktop]:-none}" != "none" ]]; then
    if confirm_yes "LibreOffice（オフィススイート・約1GB）をインストールしますか？（推奨）"; then
      CONFIG[install_office]="yes"; print_ok "LibreOffice を導入"
    else
      CONFIG[install_office]="no"; print_ok "LibreOffice はスキップ"
    fi
  else
    CONFIG[install_office]="no"
  fi

  # Google Chrome（AUR）— base-devel + AUR ヘルパーを自動で連動有効化
  if confirm_yes "Google Chrome をインストールしますか？（AUR・推奨）"; then
    CONFIG[install_chrome]="yes"
    CONFIG[extra_base_devel]="yes"
    [[ "${CONFIG[aur_helper]}" == "none" ]] && CONFIG[aur_helper]="yay"
    print_ok "Google Chrome をインストール（base-devel + ${CONFIG[aur_helper]} を自動有効化）"
  else
    CONFIG[install_chrome]="no"; print_ok "Google Chrome はスキップ"
  fi

  # yt-fzf-sh（GitHub の PKGBUILD・fzf/yt-dlp を使う対話的 YouTube ツール）
  # coffee版: 既定は No（必要な人だけが選ぶ任意ツール）
  if confirm "yt-fzf-sh をインストールしますか？（fzf/yt-dlp の YouTube ダウンローダ）"; then
    CONFIG[install_ytfzf]="yes"
    CONFIG[extra_base_devel]="yes"   # makepkg に base-devel が必要
    print_ok "yt-fzf-sh をインストール（コマンド: yt-fzf）"
  else
    CONFIG[install_ytfzf]="no"; print_ok "yt-fzf-sh はスキップ"
  fi

  # AUR ヘルパー（Chrome を入れない場合のみ個別に確認）
  if [[ "${CONFIG[install_chrome]}" != "yes" ]]; then
    if confirm_yes "AUR ヘルパー（yay）をインストールしますか？（AUR パッケージ導入用・推奨）"; then
      CONFIG[extra_base_devel]="yes"
      # ヘルパーは yay 固定（paru を使いたい上級者は後から自分で導入できる）
      CONFIG[aur_helper]="yay"
      print_ok "AUR ヘルパー: yay（固定）"
    else
      CONFIG[aur_helper]="none"
      # yt-fzf 用に base-devel が必要な場合は無効化しない
      [[ "${CONFIG[install_ytfzf]:-no}" == "yes" ]] || CONFIG[extra_base_devel]="no"
      print_ok "AUR ヘルパーはスキップ"
    fi
  fi

  # ufw（任意）— SSH と併用する場合は 22 番ポートを自動許可
  # coffee版: 既定は Yes（ノート PC を外のネットワークにつなぐ前提で守りを固める）
  if confirm_yes "ufw（ファイアウォール）を有効にしますか？"; then
    CONFIG[extra_ufw]="yes"; print_ok "ufw を有効化"
  else
    CONFIG[extra_ufw]="no"
  fi

  # その他の追加パッケージ
  local extra
  extra=$(ask "その他の追加パッケージ（スペース区切り、不要なら空 Enter）" "")
  CONFIG[extra_pkgs]="$extra"
  # 【重要】ここを `[[ -n "$extra" ]] && print_ok ...` と書いてはいけない。
  # 関数の最後の文になるため、$extra が空（＝Enter だけ押した通常の操作）だと
  # 関数の戻り値が 1 になり、set -e で呼び出し元ごと即死する。
  # 「何も言わずに終了する」現象の原因になっていた。
  if [[ -n "$extra" ]]; then
    print_ok "追加パッケージ: $extra"
  fi
}

# ============================================
# 設定サマリー表示
# ============================================

show_summary() {
  print_step "インストール設定サマリー"

  echo -e "  ${BOLD}ディスク      :${RESET} ${CONFIG[disk]}"
  echo -e "  ${BOLD}パーティション :${RESET} ${CONFIG[partition_scheme]}"
  echo -e "  ${BOLD}ファイルシステム:${RESET} ${CONFIG[fs_type]}"
  echo -e "  ${BOLD}ホスト名      :${RESET} ${CONFIG[hostname]}"
  echo -e "  ${BOLD}タイムゾーン  :${RESET} ${CONFIG[timezone]}"
  echo -e "  ${BOLD}Windows       :${RESET} $([[ "${CONFIG[windows_found]:-no}" == "yes" ]] && echo "検出（時刻を Windows に合わせ、起動メニューに表示）" || echo "検出なし（時刻は UTC）")"
  echo -e "  ${BOLD}ロケール      :${RESET} ${CONFIG[locale]}"
  echo -e "  ${BOLD}キーマップ    :${RESET} ${CONFIG[keymap]}"
  if [[ "${CONFIG[japanese_env]}" == "yes" ]]; then
    echo -e "  ${BOLD}IME           :${RESET} ${CONFIG[jp_ime]:-none}"
  fi
  if [[ -n "${CONFIG[font_pkgs]}" ]]; then
    echo -e "  ${BOLD}フォント      :${RESET} ${CONFIG[font_pkgs]}"
  fi
  echo -e "  ${BOLD}ファームウェア :${RESET} ${CONFIG[boot_mode]}"
  echo -e "  ${BOLD}ブートローダー :${RESET} ${CONFIG[bootloader]}"
  echo -e "  ${BOLD}WiFi バックエンド:${RESET} ${CONFIG[wifi_backend]}"
  echo -e "  ${BOLD}systemd-resolved:${RESET} ${CONFIG[use_resolved]}"
  echo -e "  ${BOLD}ミラー          :${RESET} reflector (Japan・固定)"
  echo -e "  ${BOLD}デスクトップ  :${RESET} COSMIC + SDDM（固定）"
  echo -e "  ${BOLD}テーマ        :${RESET} ${THEME_LABEL} (${THEME})"
  # 設定の引き継ぎ元を日本語で表示する（host/git/none のままだと分かりにくい）
  local _cfgsrc_label
  case "${CONFIG[config_source]:-host}" in
    host)    _cfgsrc_label="ホストPCの設定" ;;
    git)     _cfgsrc_label="GitHub (${ESCA_DOTFILES_REPO##*/})" ;;
    *)       _cfgsrc_label="なし（既定設定のみ）" ;;
  esac
  echo -e "  ${BOLD}設定の引き継ぎ :${RESET} ${_cfgsrc_label}"
  echo -e "  ${BOLD}GPU ドライバ   :${RESET} ${CONFIG[gpu_driver]}"
  echo -e "  ${BOLD}base-devel    :${RESET} ${CONFIG[extra_base_devel]}"
  echo -e "  ${BOLD}AUR ヘルパー   :${RESET} ${CONFIG[aur_helper]}"
  echo -e "  ${BOLD}Google Chrome :${RESET} ${CONFIG[install_chrome]:-no}"
  echo -e "  ${BOLD}yt-fzf-sh     :${RESET} ${CONFIG[install_ytfzf]:-no}"
  echo -e "  ${BOLD}OpenSSH       :${RESET} ${CONFIG[extra_ssh]}"
  echo -e "  ${BOLD}ufw (FW)      :${RESET} ${CONFIG[extra_ufw]}"
  echo -e "  ${BOLD}zram          :${RESET} ${CONFIG[extra_zram]}"
  echo -e "  ${BOLD}fstrim.timer  :${RESET} ${CONFIG[extra_fstrim]:-no}"
  if [[ "${CONFIG[desktop]:-none}" != "none" ]]; then
    echo -e "  ${BOLD}LibreOffice   :${RESET} ${CONFIG[install_office]:-no}"
  fi
  if [[ "${CONFIG[virt_env]}" != "none" ]]; then
    echo -e "  ${BOLD}仮想環境      :${RESET} ${CONFIG[virt_env]} (ゲストツール自動有効化)"
  fi
  if [[ "${CONFIG[dry_run]}" == "yes" ]]; then
    echo -e "  ${BOLD}ドライラン    :${RESET} ${RED}有効 (実行はスキップされます)${RESET}"
  fi
  [[ -n "${CONFIG[extra_pkgs]}" ]] && \
    echo -e "  ${BOLD}追加パッケージ :${RESET} ${CONFIG[extra_pkgs]}"
  if [[ "${CONFIG[users_count]:-0}" -gt 0 ]]; then
    echo -e "  ${BOLD}ユーザー      :${RESET}"
    while IFS= read -r entry; do
      [[ -z "$entry" ]] && continue
      parse_users_line "$entry"
      echo -e "    ${CYAN}•${RESET} ${uname}  sudo: ${usudo}  shell: ${ushell}"
    done <<< "${CONFIG[users]}"
  else
    echo -e "  ${BOLD}ユーザー      :${RESET} root のみ"
  fi

  echo ""
  print_warn "上記の設定でインストールを開始します。"
  print_warn "ディスク ${CONFIG[disk]} の全データが消去されます！"
}

# ============================================
# 実行: パーティション
# ============================================

do_partition() {
  local disk="${CONFIG[disk]}"
  local scheme="${CONFIG[partition_scheme]}"
  local boot_mode="${CONFIG[boot_mode]}"

  print_step "パーティション処理"

  if [[ "$scheme" == "manual" ]]; then
    if [[ "${CONFIG[dry_run]}" == "yes" ]]; then
      print_warn "ドライランのため fdisk 起動をスキップします"
      return
    fi
    print_warn "fdisk を起動します。終了後 Enter を押してください。"
    fdisk "$disk"
    return
  fi

  # ハイバネート用 swap サイズ: RAM と同容量（GiB 切り上げ・最低 4G）を確保する。
  # 固定 4G だと RAM が 4GB を超えるマシンでハイバネートに失敗するため。
  local swap_size="4G"
  if [[ "$scheme" == "auto_swap" ]]; then
    local mem_kb
    mem_kb=$(grep -m1 '^MemTotal' /proc/meminfo | awk '{print $2}')
    if [[ "$mem_kb" =~ ^[0-9]+$ ]] && [[ "$mem_kb" -gt 0 ]]; then
      local mem_gib=$(( (mem_kb + 1048575) / 1048576 ))
      [[ "$mem_gib" -lt 4 ]] && mem_gib=4
      swap_size="${mem_gib}G"
    fi
    print_ok "swap サイズ: ${swap_size}（ハイバネート用に RAM 同容量を確保）"
  fi

  # 対象ディスクのパーティションが既にマウントされていれば全てアンマウント
  run_cmd "既存マウントの解除" bash -c "
    for mp in \$(lsblk -lno MOUNTPOINT '${disk}' 2>/dev/null | grep -v '^$' | sort -r); do
      umount -f \"\$mp\" 2>/dev/null || true
    done
    swapoff -a 2>/dev/null || true
  "

  # GPT で全消去（--zap-all は GPT/MBR 双方を破棄し、以降の --new で新規GPTが作られる）
  run_cmd "GPT テーブル初期化" sgdisk --zap-all "$disk"

  if [[ "$boot_mode" == "uefi" ]]; then
    # EFI パーティション (512MB)
    run_cmd "EFI パーティション作成" \
      sgdisk --new=1:0:+512M --typecode=1:ef00 --change-name=1:EFI "$disk"

    if [[ "$scheme" == "auto_swap" ]]; then
      # swap (RAM 同容量)
      run_cmd "swap パーティション作成 (${swap_size})" \
        sgdisk --new=2:0:+"${swap_size}" --typecode=2:8200 --change-name=2:swap "$disk"
      # root (残り全部)
      run_cmd "root パーティション作成" \
        sgdisk --new=3:0:0 --typecode=3:8300 --change-name=3:root "$disk"
    else
      # root (残り全部)
      run_cmd "root パーティション作成" \
        sgdisk --new=2:0:0 --typecode=2:8300 --change-name=2:root "$disk"
    fi
  else
    # BIOS: BIOS Boot (1MB) + swap + root
    run_cmd "BIOS Boot パーティション作成" \
      sgdisk --new=1:0:+1M --typecode=1:ef02 "$disk"

    if [[ "$scheme" == "auto_swap" ]]; then
      run_cmd "swap パーティション作成 (${swap_size})" \
        sgdisk --new=2:0:+"${swap_size}" --typecode=2:8200 --change-name=2:swap "$disk"
      run_cmd "root パーティション作成" \
        sgdisk --new=3:0:0 --typecode=3:8300 --change-name=3:root "$disk"
    else
      run_cmd "root パーティション作成" \
        sgdisk --new=2:0:0 --typecode=2:8300 --change-name=2:root "$disk"
    fi
  fi

  # カーネルにパーティションテーブル再読込を通知
  # partprobe だけでは不十分な場合があるため複数手段を使う
  run_cmd "パーティションテーブル再読込 (partprobe)" partprobe "$disk"
  # blockdev --rereadpt はビジー状態でエラーになることがあるため無視
  blockdev --rereadpt "$disk" 2>/dev/null || true
  udevadm settle 2>/dev/null || true
  sleep 1

  # パーティションデバイスが実際に存在するまで最大30秒待機
  local first_part
  first_part=$(part_suffix "$disk" 1)
  local waited=0
  while [[ ! -b "$first_part" ]] && [[ "$waited" -lt 30 ]]; do
    sleep 1
    waited=$(( waited + 1 ))
    # 5秒経っても認識されなければ再度 partprobe を試みる
    if [[ "$waited" -eq 5 ]]; then
      partprobe "$disk" 2>/dev/null || true
      udevadm settle 2>/dev/null || true
    fi
  done
  if [[ ! -b "$first_part" ]]; then
    echo "エラー: パーティション ($first_part) がカーネルに認識されませんでした。" >> "${CONFIG[log_file]}"
    echo "--- dmesg ---" >> "${CONFIG[log_file]}"
    dmesg | tail -20 >> "${CONFIG[log_file]}" 2>/dev/null || true
    echo "--- lsblk ---" >> "${CONFIG[log_file]}"
    lsblk >> "${CONFIG[log_file]}" 2>/dev/null || true
    print_err "パーティション ($first_part) がカーネルに認識されませんでした。"
    print_err "ログを確認してください: ${CONFIG[log_file]}"
    exit 1
  fi
  print_ok "パーティションをカーネルが認識しました (${waited}秒待機)"
}

# ============================================
# ユーティリティ: ルートパーティションをフォーマット
# CONFIG[fs_type] に応じて適切な mkfs を呼ぶ
# ============================================

_format_root() {
  local part="$1"
  local fs="${CONFIG[fs_type]:-ext4}"
  case "$fs" in
    ext4)  run_cmd "root フォーマット (ext4)"  mkfs.ext4  -F "$part" ;;
    btrfs) run_cmd "root フォーマット (btrfs)" mkfs.btrfs -f "$part" ;;
    xfs)   run_cmd "root フォーマット (xfs)"   mkfs.xfs   -f "$part" ;;
    *)     run_cmd "root フォーマット (ext4)"  mkfs.ext4  -F "$part" ;;
  esac
}

_mount_root() {
  local part="$1"
  local fs="${CONFIG[fs_type]:-ext4}"

  # フォーマット直後にデバイスが準備完了するまで待機（失敗しても続行）
  udevadm settle 2>/dev/null || true
  sleep 1

  case "$fs" in
    btrfs)
      # btrfs: まずサブボリューム作成のために一時マウント
      run_cmd "btrfs 一時マウント" mount -t btrfs "$part" /mnt

      # @, @home, @log, @cache サブボリュームを作成
      run_cmd "btrfs サブボリューム @ 作成"    btrfs subvolume create /mnt/@
      run_cmd "btrfs サブボリューム @home 作成" btrfs subvolume create /mnt/@home
      run_cmd "btrfs サブボリューム @log 作成"  btrfs subvolume create /mnt/@log
      run_cmd "btrfs サブボリューム @cache 作成" btrfs subvolume create /mnt/@cache

      # 一時マウントを解除して正式にサブボリュームでマウント
      run_cmd "btrfs 一時アンマウント" umount /mnt

      local btrfs_opts="compress=zstd,noatime,space_cache=v2"
      run_cmd "root マウント (btrfs @)" \
        mount -t btrfs -o "${btrfs_opts},subvol=@" "$part" /mnt

      run_cmd "/home ディレクトリ作成" mkdir -p /mnt/home
      run_cmd "home マウント (btrfs @home)" \
        mount -t btrfs -o "${btrfs_opts},subvol=@home" "$part" /mnt/home

      run_cmd "/var/log ディレクトリ作成" mkdir -p /mnt/var/log
      run_cmd "log マウント (btrfs @log)" \
        mount -t btrfs -o "${btrfs_opts},subvol=@log" "$part" /mnt/var/log

      run_cmd "/var/cache ディレクトリ作成" mkdir -p /mnt/var/cache
      run_cmd "cache マウント (btrfs @cache)" \
        mount -t btrfs -o "${btrfs_opts},subvol=@cache" "$part" /mnt/var/cache
      ;;
    xfs)
      run_cmd "root マウント (xfs)" mount -t xfs "$part" /mnt
      ;;
    *)
      run_cmd "root マウント (ext4)" mount -t ext4 "$part" /mnt
      ;;
  esac
}

# ============================================
# 実行: フォーマット & マウント
# ============================================

do_format_and_mount() {
  local disk="${CONFIG[disk]}"
  local scheme="${CONFIG[partition_scheme]}"
  local boot_mode="${CONFIG[boot_mode]}"
  local efi_part="" swap_part="" root_part=""

  print_step "フォーマット & マウント"

  # 手動パーティションの場合はユーザーが自分でマウントするか、アシスタントを使う
  if [[ "$scheme" == "manual" ]]; then
    if [[ "${CONFIG[dry_run]}" == "yes" ]]; then
      print_warn "ドライランのため手動マウント処理をスキップします"
      return
    fi
    echo ""
    print_warn "手動パーティションモードです。"

    local mount_method
    mount_method=$(select_from_list "マウント方法を選択してください:" \
      "対話型アシスタントを使用（推奨・スクリプト内でマウントを指定）" \
      "手動でマウントする（別ターミナルなどでマウント済みの状態にする）")

    if [[ "$mount_method" == "対話型アシスタントを使用（推奨・スクリプト内でマウントを指定）" ]]; then
      echo ""
      print_warn "検出されたパーティション一覧:"
      lsblk -p "$disk" 2>/dev/null || fdisk -l "$disk" 2>/dev/null || ls "/sys/block/${disk#/dev/}/" || true
      echo ""

      local root_p=""
      while true; do
        root_p=$(ask "Root (/) パーティションのデバイスパスを指定してください (例: /dev/sda2)")
        if [[ -b "$root_p" ]]; then
          break
        fi
        print_err "有効なブロックデバイスではありません: $root_p"
      done

      if confirm "Root パーティション ($root_p) を ${CONFIG[fs_type]:-ext4} でフォーマットしますか？（※既存データは消去されます）"; then
        _format_root "$root_p"
      fi
      _mount_root "$root_p"
      CONFIG[root_part]="$root_p"

      # UEFI の場合
      if [[ "$boot_mode" == "uefi" ]]; then
        local efi_p=""
        while true; do
          efi_p=$(ask "EFI パーティションのデバイスパスを指定してください (例: /dev/sda1)")
          if [[ -b "$efi_p" ]]; then
            break
          fi
          print_err "有効なブロックデバイスではありません: $efi_p"
        done

        if confirm "EFI パーティション ($efi_p) を FAT32 でフォーマットしますか？"; then
          run_cmd "EFI フォーマット (FAT32)" mkfs.fat -F32 "$efi_p"
        fi
        run_cmd "EFI ディレクトリ作成" mkdir -p /mnt/boot
        run_cmd "EFI マウント" mount -t vfat "$efi_p" /mnt/boot
      fi

      # Swap
      local swap_p=""
      swap_p=$(ask "Swap パーティションのデバイスパスを指定してください（不要なら空 Enter）" "")
      if [[ -n "$swap_p" ]]; then
        if [[ -b "$swap_p" ]]; then
          if confirm "Swap パーティション ($swap_p) をフォーマットして有効化しますか？"; then
            run_cmd "swap フォーマット" mkswap "$swap_p"
          fi
          run_cmd "swap 有効化" swapon "$swap_p"
          CONFIG[swap_part]="$swap_p"
        else
          print_warn "有効なデバイスではないため swap はスキップされました: $swap_p"
        fi
      fi
    else
      # 従来の手動マウントガイド
      echo -e "  インストール先のパーティションを手動でマウントしてください。\n"
      echo -e "  ${BOLD}例（UEFI・/dev/sda の場合）:${RESET}"
      echo -e "    mount /dev/sda2 /mnt"
      echo -e "    mkdir -p /mnt/boot"
      echo -e "    mount /dev/sda1 /mnt/boot   # EFI パーティション"
      echo -e "    swapon /dev/sda3            # swap がある場合\n"
      if ! confirm "マウント完了しましたか？"; then
        print_err "中断しました。"
        exit 1
      fi
    fi

    # マウント確認
    if ! mountpoint -q /mnt; then
      print_err "/mnt がマウントされていません。"
      exit 1
    fi
    if [[ "$boot_mode" == "uefi" ]] && ! mountpoint -q /mnt/boot; then
      print_err "/mnt/boot がマウントされていません（UEFI には必須）。"
      exit 1
    fi

    # 「別ターミナルで自分でマウントした」場合は CONFIG が空のままなので、
    # 実際のマウント状態から root / swap を逆引きしておく。
    # これを埋めておかないと resume フックとカーネルの resume= がズレる。
    if [[ -z "${CONFIG[root_part]}" ]]; then
      CONFIG[root_part]=$(findmnt -no SOURCE /mnt 2>/dev/null | head -n1 | sed 's/\[.*\]$//')
      [[ -n "${CONFIG[root_part]}" ]] && print_ok "root パーティションを検出: ${CONFIG[root_part]}"
    fi
    if [[ -z "${CONFIG[swap_part]}" ]]; then
      CONFIG[swap_part]=$(swapon --show=NAME --noheadings 2>/dev/null | head -n1)
      [[ -n "${CONFIG[swap_part]}" ]] && print_ok "swap パーティションを検出: ${CONFIG[swap_part]}"
    fi

    print_ok "マウント確認OK"
    return
  fi

  if [[ "$boot_mode" == "uefi" ]]; then
    efi_part=$(part_suffix "$disk" 1)

    if [[ "$scheme" == "auto_swap" ]]; then
      swap_part=$(part_suffix "$disk" 2)
      root_part=$(part_suffix "$disk" 3)
    else
      root_part=$(part_suffix "$disk" 2)
    fi
    CONFIG[root_part]="$root_part"
    CONFIG[swap_part]="$swap_part"

    echo "[DEBUG] EFI フォーマット開始: $efi_part" >> "${CONFIG[log_file]}"
    run_cmd "EFI フォーマット (FAT32)"  mkfs.fat -F32 "$efi_part"
    echo "[DEBUG] root フォーマット開始: $root_part (fs=${CONFIG[fs_type]})" >> "${CONFIG[log_file]}"
    _format_root "$root_part"
    echo "[DEBUG] _format_root 完了" >> "${CONFIG[log_file]}"
    if [[ -n "$swap_part" ]]; then
      run_cmd "swap フォーマット" mkswap "$swap_part"
    fi
    echo "[DEBUG] _mount_root 開始: $root_part" >> "${CONFIG[log_file]}"
    _mount_root "$root_part"
    echo "[DEBUG] _mount_root 完了" >> "${CONFIG[log_file]}"
    run_cmd "EFI ディレクトリ作成" mkdir -p /mnt/boot
    echo "[DEBUG] EFI マウント開始: $efi_part" >> "${CONFIG[log_file]}"
    run_cmd "EFI マウント" mount -t vfat "$efi_part" /mnt/boot
    echo "[DEBUG] EFI マウント完了" >> "${CONFIG[log_file]}"
    # 【重要】`[[ -n ... ]] && run_cmd ... || true` と書かないこと。
    # swap_part が空のときだけでなく、swapon が「失敗したとき」も || true が
    # 拾ってしまい、swap が有効化できていないのに成功扱いで先へ進む。
    # 条件は必ず if で明示し、run_cmd の失敗はそのまま止める。
    if [[ -n "$swap_part" ]]; then
      run_cmd "swap 有効化" swapon "$swap_part"
    fi

  else
    # BIOS（efi_part/swap_part/root_part は関数先頭で local 宣言済み）
    if [[ "$scheme" == "auto_swap" ]]; then
      swap_part=$(part_suffix "$disk" 2)
      root_part=$(part_suffix "$disk" 3)
    else
      root_part=$(part_suffix "$disk" 2)
    fi
    CONFIG[root_part]="$root_part"
    CONFIG[swap_part]="$swap_part"

    _format_root "$root_part"
    # 【重要】UEFI 側と同じ理由で `&& ... || true` は使わない。
    if [[ -n "$swap_part" ]]; then
      run_cmd "swap フォーマット" mkswap "$swap_part"
    fi

    _mount_root "$root_part"
    if [[ -n "$swap_part" ]]; then
      run_cmd "swap 有効化" swapon "$swap_part"
    fi
  fi
}

# ============================================
# ネットワーク疎通確認
# ============================================

step_check_network() {
  print_step "ネットワーク確認"
  echo -ne "  ${CYAN}…${RESET} インターネット接続を確認中..."
  # ICMP を遮断する環境があるため、ping が失敗しても HTTPS 疎通を確認する
  if ping -c1 -W3 archlinux.org &>/dev/null || curl -sf -m5 https://archlinux.org -o /dev/null; then
    echo -e "\r  ${GREEN}✔${RESET} インターネット接続OK"
  else
    echo -e "\r  ${RED}✘${RESET} インターネットに接続できません"
    echo ""
    print_warn "有線接続の場合: ケーブルを確認してください"
    print_warn "WiFi の場合  : iwctl で接続してください"
    echo -e "\n  ${BOLD}iwctl の使い方:${RESET}"
    echo "    iwctl"
    echo "    [iwd]# device list"
    echo "    [iwd]# station wlan0 scan"
    echo "    [iwd]# station wlan0 get-networks"
    echo "    [iwd]# station wlan0 connect <SSID>"
    echo ""
    if ! confirm "接続できました。続けますか？"; then
      print_err "中断しました。"
      exit 1
    fi
    # 再確認
    echo -ne "  ${CYAN}…${RESET} 再確認中..."
    if ping -c1 -W5 archlinux.org &>/dev/null || curl -sf -m8 https://archlinux.org -o /dev/null; then
      echo -e "\r  ${GREEN}✔${RESET} インターネット接続OK"
    else
      echo -e "\r  ${RED}✘${RESET} まだ接続できません。終了します。"
      exit 1
    fi
  fi

  # Live ISO の時刻を NTP で同期
  # （狂ったままだと pacman の署名検証が失敗することがある）
  echo -ne "  ${CYAN}…${RESET} NTP 時刻同期中..."
  timedatectl set-ntp true
  # 最大10秒待って同期を確認
  local i
  for i in {1..10}; do
    if timedatectl status 2>/dev/null | grep -q "synchronized: yes"; then
      echo -e "\r  ${GREEN}✔${RESET} NTP 時刻同期完了: $(date '+%Y-%m-%d %H:%M:%S %Z')"
      return
    fi
    sleep 1
  done
  echo -e "\r  ${YELLOW}⚠${RESET} NTP 同期タイムアウト（続行します）"
  echo -e "    現在時刻: $(date '+%Y-%m-%d %H:%M:%S %Z')"
}

# ============================================
# ステップ: ネットワーク設定（インストール後）
# ============================================

step_network() {
  print_step "ネットワーク設定"

  # WiFi バックエンド選択
  local wifi_backend
  wifi_backend=$(select_from_list "WiFi バックエンドを選択:" \
    "iwd（軽量・高速・推奨）" \
    "wpa_supplicant（古くから使われている実装・互換性重視）" \
    "なし（有線のみ・後から設定）")

  case "$wifi_backend" in
    "iwd（軽量・高速・推奨）")                              CONFIG[wifi_backend]="iwd" ;;
    "wpa_supplicant（古くから使われている実装・互換性重視）") CONFIG[wifi_backend]="wpa_supplicant" ;;
    "なし（有線のみ・後から設定）")                          CONFIG[wifi_backend]="none" ;;
  esac
  print_ok "WiFi バックエンド: ${CONFIG[wifi_backend]}"

  # systemd-resolved: 推奨のため固定で有効化
  # （DNS キャッシュ・DNSSEC。NetworkManager と自動連携する）
  CONFIG[use_resolved]="yes"
  print_ok "systemd-resolved: 有効（固定）"
}

# ============================================
# ステップ: ミラーサーバー設定
# ============================================

step_mirror() {
  print_step "ミラーサーバー設定"

  # 日本語特化のため reflector --country Japan 固定。
  # （reflector が失敗した場合は Live ISO の既存リストで続行する。do_mirrorlist 参照）
  CONFIG[mirror_country]="Japan"
  print_ok "ミラー: reflector で日本国内の速いミラーを自動選択（固定）"
}

# ============================================
# 実行: ミラーリスト設定
# ============================================

do_mirrorlist() {
  print_step "ミラーリスト設定"

  # 日本語特化のため reflector（--country Japan）固定
  # reflector が入っていなければインストール
  if ! command -v reflector &>/dev/null; then
    run_cmd_retry "reflector インストール" pacman -S --noconfirm reflector
  fi

  # 日本国内・HTTPS・最終同期24時間以内・速度順 上位8件
  #
  # 【重要】reflector の失敗でインストール全体を止めないこと。
  # Live ISO の mirrorlist は起動時に既に reflector で作られており、
  # 速さで劣るだけでそのまま使える。失敗したら元のリストに戻して続行する。
  # 成功扱いでも条件に合うミラーが0件だと Server 行の無いリストが残るため、
  # 中身も確認する（空のリストのままだと pacstrap が原因の分かりにくい形で落ちる）。
  local ml="/etc/pacman.d/mirrorlist" ml_bak="/tmp/esca-mirrorlist.bak"
  local desc="reflector 実行（Japan・速度順）"
  if [[ "${CONFIG[dry_run]}" == "yes" ]]; then
    print_warn "${desc} (ドライラン - スキップ)"
    return 0
  fi
  cp -f "$ml" "$ml_bak" 2>/dev/null || true
  echo -ne "  ${CYAN}…${RESET} ${desc}..."
  if _exec_timed "$desc" \
       reflector --country "${CONFIG[mirror_country]:-Japan}" \
         --protocol https \
         --age 24 \
         --sort rate \
         --number 8 \
         --save "$ml" \
     && grep -q '^Server' "$ml" 2>/dev/null; then
    echo -e "\r  ${GREEN}✔${RESET} ${desc}                              "
  else
    echo -e "\r  ${YELLOW}⚠${RESET} ${desc} — 失敗                              "
    if [[ -f "$ml_bak" ]]; then
      cp -f "$ml_bak" "$ml" 2>/dev/null || true
    fi
    print_warn "Live ISO の既存ミラーリストで続行します（ログ: ${CONFIG[log_file]}）"
  fi
  if ! grep -q '^Server' "$ml" 2>/dev/null; then
    print_err "使用できるミラーがありません（${ml} に Server 行がありません）。"
    print_err "ネットワークを確認してから再実行してください。ディスクにはまだ触れていません。"
    exit 1
  fi
  print_ok "選択されたミラー:"
  grep '^Server' /etc/pacman.d/mirrorlist | sed 's/^/    /' || true
}

# ============================================
# 実行: ベースインストール
# ============================================

do_pacstrap() {
  print_step "ベースシステムのインストール"

  # pacman キーリング初期化（Live ISO では既に初期化済みの場合はスキップ）
  if [[ ! -f /etc/pacman.d/gnupg/trustdb.gpg ]]; then
    run_cmd "pacman キーリング初期化" pacman-key --init
  else
    print_ok "pacman キーリング初期化済み（スキップ）"
  fi
  run_cmd "Arch キーリング追加" pacman-key --populate archlinux
  # Live ISOのキーリングを最新化（署名エラー防止）
  # ※ この -Sy でパッケージDBも同時に更新されるため、追加の -Syy は不要
  #   （-Syy は全ミラーDBの強制再取得で、直後に行うと単なる二重ダウンロードになる）
  run_cmd_retry "Live ISO キーリング更新 + パッケージDB更新" pacman -Sy --noconfirm archlinux-keyring

  # 【重要】vim を入れても `vi` コマンドは使えない。
  # Arch は vi パッケージの提供を終了しており、vim パッケージは
  # /usr/bin/vi を作らないため、vi と打つと command not found になる。
  # ex-vi-compat が /usr/bin/vi と /usr/bin/ex を vim へのシンボリックリンクとして
  # 提供するので、これを併せて入れる。
  # （visudo や systemctl edit は EDITOR 未設定時に vi を呼ぶため、
  #   これが無いと編集そのものが起動しない場面がある）
  local pkgs=(base sudo linux linux-firmware sof-firmware networkmanager vim ex-vi-compat)

  # ファイルシステム操作ツール一式
  # GNOME Disks や KDE Partition Manager などの GUI は mkfs.* を外部コマンドとして
  # 呼び出すため、これらが無いと「フォーマット形式の候補に出てこない」状態になる。
  # base には dosfstools すら含まれないので、DE の有無に関わらずここで入れる。
  local fs_tools=(
    dosfstools    # FAT12/16/32 — SD カード・USB メモリ・EFI で最頻出
    exfatprogs    # exFAT — 大容量 SD カード、デジカメ
    ntfs-3g       # NTFS のマウント用 FUSE ドライバ
    # 【重要】mkfs.ntfs / mkntfs は ntfs-3g には入っていない。
    # Arch は 2026年5月に ntfs-3g を分割し、ドライバ = ntfs-3g、
    # ユーティリティ = ntfsprogs になった（以前は provides で同一だった）。
    # これが無いと GUI に NTFS のフォーマット候補が出てこない。
    ntfsprogs     # NTFS の作成・修復・リサイズ (mkntfs, ntfsfix, ntfsresize)
    btrfs-progs   # Btrfs
    xfsprogs      # XFS
    f2fs-tools    # F2FS — フラッシュメモリ向け
    udftools      # UDF — 光学メディア・大容量可搬メディア
    e2fsprogs     # ext2/3/4（base にも含まれるが依存を明示する）
    mtools        # FAT をマウントせずに操作する
    parted        # パーティション操作（GUI ツールが libparted 経由で使う）
  )
  pkgs+=("${fs_tools[@]}")

  # root のファイルシステムに応じた案内（パッケージ自体は上で導入済み）
  case "${CONFIG[fs_type]:-ext4}" in
    btrfs) print_ok "root は Btrfs（btrfs-progs 導入済み）" ;;
    xfs)   print_ok "root は XFS（xfsprogs 導入済み）" ;;
  esac

  # WiFi バックエンド
  case "${CONFIG[wifi_backend]}" in
    wpa_supplicant) pkgs+=(wpa_supplicant) ;;
    iwd)            pkgs+=(iwd) ;;
  esac

  # マイクロコード
  local cpu_vendor="${CONFIG[cpu_vendor]}"
  if [[ "$cpu_vendor" == "GenuineIntel" ]]; then
    pkgs+=(intel-ucode)
    print_ok "Intel マイクロコードを追加"
  elif [[ "$cpu_vendor" == "AuthenticAMD" ]]; then
    pkgs+=(amd-ucode)
    print_ok "AMD マイクロコードを追加"
  fi

  # コンソール（TTY）フォント。
  # 既定の 8x16 フォントは高解像度パネルだと極端に小さく読みにくい。
  # また X / Wayland が起動しない障害時に TTY だけが復旧手段になるため、
  # デスクトップの有無に関わらず全インストールで入れておく。
  pkgs+=(terminus-font)

  # starship プロンプト（全インストール共通）。
  # 【重要】do_desktop 側ではなくここで入れること。
  # do_desktop は desktop=none で早期 return するため、そちらに置くと
  # CLI のみの構成でプロンプト初期化だけが .bashrc に残り、
  # シェルを開くたびに starship が見つからない状態になる
  # （init 側は command -v で守ってあるが、本体が無いこと自体が想定外）。
  pkgs+=(starship)

  # 汎用 CLI ツール（全インストール共通）。
  # 【重要】starship と同じ理由で do_desktop 側ではなくここに置くこと。
  # do_desktop は desktop=none で早期 return するため、そちらに置くと
  # CLI のみの構成にだけ入らない。これらはターミナルから使う道具なので、
  # デスクトップ環境の有無で入る／入らないが変わるのは筋が通らない。
  #
  # かつて streamlink を Hyprland / Niri の pkgs にだけ置いていた時期があり、
  # 「GNOME に streamlink が入らない」という取りこぼしが実際に起きた。
  # 特定の WM やパネルの依存として扱わず、必ずこの一箇所で管理する。
  # 5つとも公式リポジトリ (extra) にあるため AUR ヘルパーは不要。
  pkgs+=(
    streamlink      # 各種配信サイトのストリーム取得（mpv へ引き渡し）
    yt-dlp          # 動画・音声のダウンロード
    sox             # 音声の変換・加工・再生 (play/rec/sox)
    imagemagick     # 画像の変換・リサイズ・一括処理 (magick)
    qrencode        # QR コード生成
  )

  # ユーザーのログインシェル（zsh / fish）を自動追加
  if [[ "${CONFIG[users]:-}" =~ \|zsh\| ]]; then
    pkgs+=(zsh)
    print_ok "ログインシェル用 zsh を追加"
  fi
  if [[ "${CONFIG[users]:-}" =~ \|fish\| ]]; then
    pkgs+=(fish)
    print_ok "ログインシェル用 fish を追加"
  fi

  # GRUB 選択時は追加パッケージ
  if [[ "${CONFIG[bootloader]}" == "grub" ]]; then
    pkgs+=(grub)
    if [[ "${CONFIG[boot_mode]}" == "uefi" ]]; then
      pkgs+=(efibootmgr)
    fi
    # Windows を検出したときは他OS検出のため os-prober を追加
    # （NTFS のマウントに必要な ntfs-3g は fs_tools で導入済み）
    if [[ "${CONFIG[windows_found]}" == "yes" ]]; then
      pkgs+=(os-prober)
      print_ok "Windows 検出のため os-prober を追加"
    fi
  fi

  # AURヘルパー/Chrome/yt-fzf 用 git の追加（いずれも clone + makepkg を使う）
  # AUR 接続確認そのものが `arch-chroot /mnt git ls-remote ...` で git を使うため、
  # git が無いとこの確認が失敗し、「AUR に接続できません／DNS の同期不良」という
  # 実態と異なる警告を出したまま処理が進む。
  if [[ "${CONFIG[aur_helper]}" != "none" || "${CONFIG[install_chrome]:-no}" == "yes" || "${CONFIG[install_ytfzf]:-no}" == "yes" ]]; then
    pkgs+=(git)
  fi

  # OpenSSH, UFW の追加
  [[ "${CONFIG[extra_ssh]}" == "yes" ]] && pkgs+=(openssh)
  [[ "${CONFIG[extra_ufw]}" == "yes" ]] && pkgs+=(ufw)

  # GPU ドライバーの追加
  case "${CONFIG[gpu_driver]}" in
    nvidia)  pkgs+=(nvidia nvidia-utils) ;;
    nouveau) pkgs+=(xf86-video-nouveau mesa) ;;
    amdgpu)  pkgs+=(xf86-video-amdgpu mesa vulkan-radeon) ;;
    intel)
      # xf86-video-intel は X11 専用。COSMIC は Wayland なので不要。
      # intel-media-driver は動画のハードウェアデコード（VA-API, iHD）。
      # Broadwell 以降（HD 620 を含む）が対象で、これが無いと Firefox や mpv の
      # 動画再生が CPU デコードになり、負荷とバッテリー消費が大きく増える。
      pkgs+=(mesa vulkan-intel intel-media-driver)
      print_ok "Intel GPU (Wayland): mesa + vulkan-intel + intel-media-driver（xf86-video-intel はスキップ）"
      ;;
    virtual) pkgs+=(xf86-video-vmware) ;;
  esac

  # 仮想環境ゲストツールの追加
  case "${CONFIG[virt_env]}" in
    oracle)             pkgs+=(virtualbox-guest-utils) ;;
    kvm|qemu)           pkgs+=(qemu-guest-agent) ;;
    vmware)             pkgs+=(open-vm-tools) ;;
  esac

  # ユーザーが選択した追加パッケージ
  # base-devel は makepkg に必須。AUR/Chrome/yt-fzf のいずれかがあれば必ず入れる。
  if [[ "${CONFIG[extra_base_devel]}" == "yes" \
        || "${CONFIG[aur_helper]}" != "none" \
        || "${CONFIG[install_chrome]:-no}" == "yes" \
        || "${CONFIG[install_ytfzf]:-no}" == "yes" ]]; then
    pkgs+=(base-devel)
  fi
  [[ "${CONFIG[extra_zram]}" == "yes" ]]       && pkgs+=(zram-generator)
  if [[ -n "${CONFIG[extra_pkgs]}" ]]; then
    read -ra _extra <<< "${CONFIG[extra_pkgs]}"
    pkgs+=("${_extra[@]}")
  fi

  # フォント
  if [[ -n "${CONFIG[font_pkgs]}" ]]; then
    read -ra _font_pkgs <<< "${CONFIG[font_pkgs]}"
    pkgs+=("${_font_pkgs[@]}")
  fi

  # 日本語環境が有効なのに CJK フォントが無い場合、文字化け（豆腐）を防ぐため
  # 最低限の日本語・絵文字フォントを自動追加する（初心者救済のセーフティネット）
  if [[ "${CONFIG[japanese_env]}" == "yes" ]]; then
    [[ " ${pkgs[*]} " == *" noto-fonts-cjk "* ]]   || { pkgs+=(noto-fonts-cjk);   print_ok "日本語表示のため noto-fonts-cjk を自動追加（豆腐防止）"; }
    [[ " ${pkgs[*]} " == *" noto-fonts "* ]]       || pkgs+=(noto-fonts)
    [[ " ${pkgs[*]} " == *" noto-fonts-emoji "* ]] || pkgs+=(noto-fonts-emoji)
  fi

  # IME（日本語特化のため fcitx5-mozc に固定）
  pkgs+=(fcitx5 fcitx5-mozc fcitx5-gtk fcitx5-qt fcitx5-configtool)

  # 【重要】FONT は KEYMAP と同じ /etc/vconsole.conf に書く。
  # 以前は KEYMAP 行だけを `>` で書き出していたため、ここで FONT を
  # 別途追記しようとすると上書きで消える。1回の書き出しにまとめる。
  #
  # ter-116n = Terminus 8x16 通常字形。標準フォントと同じ高さのまま
  # 字形が読みやすくなる無難な既定値。高解像度パネルで小さすぎる場合は
  # ter-124n / ter-132n（12x24 / 16x32）に変更する。
  #
  # 【注意】コンソールフォントは PSF 形式で収録グリフ数に上限があり、
  # Nerd Font のアイコンや Powerline 区切り記号は表示できない。
  # TTY で starship の記号が豆腐になる場合はフォントではなくプリセット側で
  # 対処する（starship preset plain-text-symbols）。
  #
  # 【重要】pacstrap より前に書くこと。vconsole.conf は initramfs の keymap /
  # consolefont フックに取り込まれる。pacstrap 中の linux 導入で initramfs が
  # 作られるので、先に置いておけばその1回で正しい内容になり、後から
  # mkinitcpio -P をやり直す必要がなくなる（インストール時間の短縮）。
  # vconsole.conf はどのパッケージも所有しないので、先に置いても衝突しない。
  run_cmd "キーマップ・コンソールフォント設定" \
    bash -c "mkdir -p /mnt/etc && printf 'KEYMAP=%s\nFONT=ter-116n\n' '${CONFIG[keymap]}' > /mnt/etc/vconsole.conf"

  run_cmd_retry "pacstrap 実行（時間がかかります）" pacstrap /mnt "${pkgs[@]}"
}
do_fstab() {
  print_step "fstab 生成"
  run_cmd "fstab 生成" bash -c "genfstab -U /mnt > /mnt/etc/fstab"
  if [[ -f /mnt/etc/fstab ]]; then
    print_ok "生成内容:"
    sed 's/^/    /' /mnt/etc/fstab
  fi
}

# ============================================
# 実行: chroot 内設定
# ============================================

# ============================================
# OS ブランディングの書き込み
# ============================================
# /etc/os-release と /etc/issue に Esca Linux の情報を書く。
#
# 【注意】Arch の /etc/os-release は filesystem パッケージが所有する
# /usr/lib/os-release へのシンボリックリンク。実ファイルで置き換えると、
# filesystem の更新時に pacman が os-release.pacnew を作る。
# 正式には自前の filesystem パッケージを用意するべきだが、
# 独自リポジトリを持つまではこの方式で問題ない。
write_os_branding() {
  run_cmd "OS 情報の書き込み (/etc/os-release)" bash -c "
    rm -f /mnt/etc/os-release
    cat > /mnt/etc/os-release <<'OSREL'
NAME=\"${OS_NAME}\"
PRETTY_NAME=\"${OS_NAME} (Arch Linux ベース)\"
ID=${OS_ID}
ID_LIKE=arch
BUILD_ID=rolling
ANSI_COLOR=\"1;33\"
HOME_URL=\"${OS_HOME_URL}\"
LOGO=${OS_ID}
OSREL
  "

  # TTY ログイン画面のバナー。\\e や \\l は agetty が解釈するため
  # ヒアドキュメントをクォートして、ここでは展開させない。
  run_cmd "コンソールバナーの書き込み (/etc/issue)" bash -c "
    cat > /mnt/etc/issue <<'ISSUE'

                    . * .
                  *  (o)  *
                    . * .
                      |
               ,------'
             ,'
        ----'

  ███████╗███████╗ ██████╗ █████╗
  ██╔════╝██╔════╝██╔════╝██╔══██╗
  █████╗  ███████╗██║     ███████║
  ██╔══╝  ╚════██║██║     ██╔══██║
  ███████╗███████║╚██████╗██║  ██║
  ╚══════╝╚══════╝ ╚═════╝╚═╝  ╚═╝

  Arch Linux ベース  ·  \\r on \\m

ISSUE
  "
}

do_chroot_config() {
  print_step "chroot 内設定"

  # タイムゾーン・時刻設定
  run_cmd "タイムゾーン設定" \
    arch-chroot /mnt ln -sf "/usr/share/zoneinfo/${CONFIG[timezone]}" /etc/localtime

  if [[ "${CONFIG[windows_found]:-no}" == "yes" ]]; then
    # Windows と共存: RTC をローカル時刻として扱う
    # timedatectl は chroot 内で動かないため /etc/adjtime を直接書く
    # ※ hwclock は RTC の無い一部の VM で失敗するため非致命扱い
    #   （挙動を決めるのは adjtime の書き込みなのでそちらが本命）
    # 【重要】run_cmd_soft は失敗時に 1 を返す。set -e 下で「|| true」を付けずに
    # 単独の文として呼ぶと、そこでインストーラ全体が停止してしまい
    # 「非致命扱い」という意図がそのまま無効になる。必ず || true を付けること。
    run_cmd_soft "RTC ローカル時刻設定（Windows 互換）" \
      arch-chroot /mnt hwclock --systohc --localtime || true
    # adjtime の3行目を LOCAL に確実に上書き（>> だと二重追記になるため > で書き直す）
    run_cmd "adjtime LOCAL 設定" bash -c \
      "printf '0.0 0 0.0\n0\nLOCAL\n' > /mnt/etc/adjtime"
  else
    # 通常: RTC を UTC として扱う（推奨）
    run_cmd_soft "RTC UTC 設定" arch-chroot /mnt hwclock --systohc --utc || true
  fi

  # systemd-timesyncd を有効化（インストール後も NTP 同期を維持）
  run_cmd "systemd-timesyncd 有効化" \
    systemctl --root=/mnt enable systemd-timesyncd

  # 日本向け NTP サーバーを設定
  if [[ "${CONFIG[timezone]}" == Asia/Tokyo* || "${CONFIG[timezone]}" == Asia/Osaka* ]]; then
    run_cmd "NTP サーバー設定（日本）" bash -c "mkdir -p /mnt/etc/systemd && \
      cat > /mnt/etc/systemd/timesyncd.conf << 'EOF'
[Time]
NTP=ntp.nict.go.jp 0.jp.pool.ntp.org 1.jp.pool.ntp.org
FallbackNTP=0.arch.pool.ntp.org 1.arch.pool.ntp.org
EOF"
    print_ok "NTP: nict.go.jp（国立研究開発法人情報通信研究機構）"
  else
    run_cmd "NTP サーバー設定（デフォルト）" bash -c "mkdir -p /mnt/etc/systemd && \
      cat > /mnt/etc/systemd/timesyncd.conf << 'EOF'
[Time]
NTP=0.arch.pool.ntp.org 1.arch.pool.ntp.org 2.arch.pool.ntp.org
FallbackNTP=0.pool.ntp.org 1.pool.ntp.org
EOF"
  fi

  # ロケール（sed のパターンで . をエスケープして誤マッチを防ぐ）
  local locale_escaped="${CONFIG[locale]//./\\.}"
  run_cmd "locale.gen 編集" \
    bash -c "sed -i 's/^#${locale_escaped}/${CONFIG[locale]}/' /mnt/etc/locale.gen"
  # en_US.UTF-8 は常に有効にしておく（一部ツールに必要）
  run_cmd "en_US.UTF-8 有効化" \
    bash -c "sed -i 's/^#en_US\\.UTF-8/en_US.UTF-8/' /mnt/etc/locale.gen"
  run_cmd "locale-gen 実行" arch-chroot /mnt locale-gen
  run_cmd "LANG 設定" \
    bash -c "echo 'LANG=${CONFIG[locale]}' > /mnt/etc/locale.conf"

  # 全ログインセッション（DM/TTY問わず pam_env が読む）で LANG を保証する。
  # /etc/locale.conf だけだと、軽量セッション（niri/Hyprland を greetd 等で起動）で
  # LANG が渡らず、漢字が中国語字形になることがあるため、二重に明示しておく。
  if [[ "${CONFIG[japanese_env]}" == "yes" ]]; then
    run_cmd "LANG を /etc/environment にも設定（全DE共通）" bash -c "
      grep -q '^LANG=' /mnt/etc/environment 2>/dev/null || echo 'LANG=${CONFIG[locale]}' >> /mnt/etc/environment
      grep -q '^LC_CTYPE=' /mnt/etc/environment 2>/dev/null || echo 'LC_CTYPE=${CONFIG[locale]}' >> /mnt/etc/environment
    "
  fi

  # キーマップ・コンソールフォント（/etc/vconsole.conf）は do_pacstrap で
  # pacstrap より前に書いている。initramfs に取り込まれるため（理由はそちら参照）。

  # X11 キーボードレイアウト設定
  # キーマップは jp106 固定のため X11 レイアウトも jp 固定
  local xkb_layout="jp"
  local xkb_model="jp106"

  if [[ -n "$xkb_layout" && "$xkb_layout" != "none" ]]; then
    run_cmd "X11 キーマップ設定" bash -c "
      mkdir -p /mnt/etc/X11/xorg.conf.d
      {
        echo 'Section \"InputClass\"'
        echo '        Identifier \"system-keyboard\"'
        echo '        MatchIsKeyboard \"on\"'
        echo \"        Option \\\"XkbLayout\\\" \\\"${xkb_layout}\\\"\"
        [[ -n \"${xkb_model}\" ]] && echo \"        Option \\\"XkbModel\\\" \\\"${xkb_model}\\\"\"
        echo 'EndSection'
      } > /mnt/etc/X11/xorg.conf.d/00-keyboard.conf
    "
  fi

  # ホスト名
  run_cmd "hostname 設定" \
    bash -c "echo '${CONFIG[hostname]}' > /mnt/etc/hostname"
  run_cmd "hosts 設定" bash -c "cat > /mnt/etc/hosts << EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   ${CONFIG[hostname]}.localdomain ${CONFIG[hostname]}
EOF"

  # ネットワーク設定
  run_cmd "NetworkManager 有効化" \
    systemctl --root=/mnt enable NetworkManager

  # WiFi バックエンド設定
  case "${CONFIG[wifi_backend]}" in
    iwd)
      run_cmd "iwd 有効化" systemctl --root=/mnt enable iwd
      # iwd 自体の自動IP取得を無効化（NetworkManager が行うため）
      run_cmd "iwd 設定" bash -c "mkdir -p /mnt/etc/iwd && cat > /mnt/etc/iwd/main.conf << 'EOF'
[General]
EnableNetworkConfiguration=false
EOF"
      # NetworkManager が iwd をバックエンドとして使うよう設定
      run_cmd "NM iwd バックエンド設定" bash -c "mkdir -p /mnt/etc/NetworkManager/conf.d && cat > /mnt/etc/NetworkManager/conf.d/wifi-backend.conf << 'EOF'
[device]
wifi.backend=iwd
EOF"
      print_ok "NetworkManager → iwd バックエンド設定完了"
      ;;
    wpa_supplicant)
      run_cmd "wpa_supplicant 有効化" \
        systemctl --root=/mnt enable wpa_supplicant
      print_ok "NetworkManager → wpa_supplicant バックエンド（デフォルト）"
      ;;
  esac

  # systemd-resolved 設定
  if [[ "${CONFIG[use_resolved]}" == "yes" ]]; then
    run_cmd "systemd-resolved 有効化" \
      systemctl --root=/mnt enable systemd-resolved
    # NetworkManager に resolved を使わせる設定
    run_cmd "NM resolved 連携設定" bash -c "mkdir -p /mnt/etc/NetworkManager/conf.d && cat > /mnt/etc/NetworkManager/conf.d/dns.conf << 'EOF'
[main]
dns=systemd-resolved
EOF"
    print_ok "systemd-resolved + NetworkManager 連携設定完了"
  fi

  # zram 設定
  if [[ "${CONFIG[extra_zram]}" == "yes" ]]; then
    run_cmd "zram 設定ファイル作成" bash -c "cat > /mnt/etc/systemd/zram-generator.conf << EOF
[zram0]
zram-size = min(ram / 2, 4096)
compression-algorithm = zstd
EOF"
    print_ok "zram: RAM の最大半分（上限 4GB）を zstd 圧縮で確保"
  fi

  # IME 環境変数（X11 / Wayland で異なる）
  if [[ "${CONFIG[jp_ime]:-none}" != "none" ]]; then
    case "${CONFIG[jp_ime]}" in
      fcitx5-mozc|fcitx5-anthy)
        # COSMIC は Wayland ネイティブで、IM モジュールを自分で解決する。
        # 【重要】GTK_IM_MODULE / QT_IM_MODULE は設定しないこと。
        # GTK3/4 は text-input-v3 を、Qt は DE 側の仕組みを使うため、
        # 明示すると二重に噛んで変換候補が出ないなどの不具合になる。
        run_cmd "fcitx5 環境変数設定 (Wayland Native DE)" bash -c "cat >> /mnt/etc/environment << 'EOF'
# fcitx5 - Wayland Native DE
# GTK_IM_MODULE / QT_IM_MODULE は意図的に未設定
# (GTK3/4 は text-input-v3、Qt は DE の virtual keyboard を使用)
XMODIFIERS=@im=fcitx
SDL_IM_MODULE=fcitx
EOF"
        ;;
    esac

    # Fcitx5 の初期設定プロファイルを生成（初回起動時から日本語入力・Mozcを使えるようにする）
    if [[ "${CONFIG[jp_ime]}" =~ ^fcitx5 ]]; then
      # キーマップは jp106 固定のためレイアウトも jp 固定
      local layout="jp"
      local kb_item="keyboard-jp"

      local default_im="mozc"

      run_cmd "Fcitx5 プロファイル初期設定" bash -c "
        mkdir -p ${SKEL_ROOT}/.config/fcitx5
        cat > ${SKEL_ROOT}/.config/fcitx5/profile << EOF
[Groups/0]
Name=Default
Default Layout=${layout}
DefaultIM=${default_im}

[Groups/0/Items/0]
Name=${kb_item}
Layout=

[Groups/0/Items/1]
Name=${default_im}
Layout=
EOF
      "
      print_ok "Fcitx5: 日本語入力の初期レイアウト・${default_im} を設定しました"
    fi

    print_ok "IME 環境変数設定完了（Wayland モード）"
  fi

  # fontconfig 優先度設定（絵文字＋日本語フォントが共存する場合）
  if [[ "${CONFIG[font_setup_fontconfig]:-no}" == "yes" ]]; then
    run_cmd "fontconfig 優先度設定" bash -c "mkdir -p /mnt/etc/fonts/conf.d && \
cat > /mnt/etc/fonts/conf.d/99-custom-fonts.conf << 'EOF'
<?xml version=\"1.0\"?>
<!DOCTYPE fontconfig SYSTEM \"fonts.dtd\">
<fontconfig>
  <!-- 絵文字フォントを最優先（カラー絵文字を他フォントより前に） -->
  <alias>
    <family>emoji</family>
    <prefer>
      <family>Noto Color Emoji</family>
    </prefer>
  </alias>
  <!-- sans-serif の日本語フォント優先順 -->
  <alias>
    <family>sans-serif</family>
    <prefer>
      <family>Noto Sans CJK JP</family>
      <family>Source Han Sans JP</family>
    </prefer>
  </alias>
  <!-- serif の日本語フォント優先順 -->
  <alias>
    <family>serif</family>
    <prefer>
      <family>Noto Serif CJK JP</family>
      <family>Source Han Serif JP</family>
    </prefer>
  </alias>
  <!-- monospace: Fira Code を優先 -->
  <alias>
    <family>monospace</family>
    <prefer>
      <family>Fira Code</family>
      <family>Fira Mono</family>
      <family>Noto Sans Mono CJK JP</family>
    </prefer>
  </alias>
  <!-- ターミナル(alacritty 等)の漢字が中国語字形(SC)になるのを防ぐ。 -->
  <!-- 等幅フォントの CJK フォールバックに 日本語字形(JP) を強制的に付加する。 -->
  <!-- prefer だけでは per-glyph フォールバックで SC が選ばれることがあるため match を併用。 -->
  <match target=\"pattern\">
    <test name=\"family\"><string>monospace</string></test>
    <edit name=\"family\" mode=\"append\" binding=\"strong\"><string>Noto Sans Mono CJK JP</string></edit>
  </match>
  <match target=\"pattern\">
    <test name=\"family\"><string>JetBrainsMono Nerd Font</string></test>
    <edit name=\"family\" mode=\"append\" binding=\"strong\"><string>Noto Sans Mono CJK JP</string></edit>
  </match>
  <match target=\"pattern\">
    <test name=\"family\"><string>Hack Nerd Font</string></test>
    <edit name=\"family\" mode=\"append\" binding=\"strong\"><string>Noto Sans Mono CJK JP</string></edit>
  </match>
  <match target=\"pattern\">
    <test name=\"family\"><string>JetBrains Mono</string></test>
    <edit name=\"family\" mode=\"append\" binding=\"strong\"><string>Noto Sans Mono CJK JP</string></edit>
  </match>
  <match target=\"pattern\">
    <test name=\"family\"><string>Fira Code</string></test>
    <edit name=\"family\" mode=\"append\" binding=\"strong\"><string>Noto Sans Mono CJK JP</string></edit>
  </match>
</fontconfig>
EOF"
    print_ok "fontconfig: 絵文字・日本語・Fira の優先度を設定しました"
  fi

  # pacman.conf の最適化
  run_cmd "pacman.conf チューニング（インストール先）" \
    bash -c "$(declare -f tune_pacman_conf); tune_pacman_conf /mnt/etc/pacman.conf"

  # ハイバネート用の resume フック追加
  # 判定は partition_scheme ではなく「実際に swap があるか」で行う。
  # do_bootloader は scheme に関わらず swap があれば resume=PARTUUID= を渡すため、
  # auto_swap 限定にすると手動パーティション+swap でフックだけ欠けて不整合になる。
  # initramfs の作り直しが要るか（mkinitcpio.conf を変更したときだけ true）。
  # 変更が無ければ pacstrap 時に作られたものがそのまま正しい。
  local initramfs_dirty="no"

  if [[ -n "${CONFIG[swap_part]}" ]]; then
    initramfs_dirty="yes"
    run_cmd "mkinitcpio.conf に resume フックを追加" bash -c "
      if grep -q '^HOOKS=' /mnt/etc/mkinitcpio.conf; then
        # アドレス指定なしだとコメント内の例示 HOOKS 行まで書き換わるため /^HOOKS=/ に限定
        sed -i '/^HOOKS=/ s/\bfilesystems\b/resume filesystems/' /mnt/etc/mkinitcpio.conf
      fi
    "
  fi

  # btrfs モジュール追加
  if [[ "${CONFIG[fs_type]}" == "btrfs" ]]; then
    initramfs_dirty="yes"
    run_cmd "mkinitcpio.conf に btrfs モジュールを追加" bash -c "
      if grep -q '^MODULES=()' /mnt/etc/mkinitcpio.conf; then
        sed -i 's/^MODULES=()/MODULES=(btrfs)/' /mnt/etc/mkinitcpio.conf
      elif grep -q '^MODULES=' /mnt/etc/mkinitcpio.conf; then
        sed -i 's/^MODULES=(\(.*\))/MODULES=(\1 btrfs)/' /mnt/etc/mkinitcpio.conf
      fi
    "
  fi

  # NVIDIA KMS 設定
  if [[ "${CONFIG[gpu_driver]}" == "nvidia" ]]; then
    initramfs_dirty="yes"
    run_cmd "mkinitcpio.conf に NVIDIA モジュールを追加" bash -c "
      if grep -q '^MODULES=' /mnt/etc/mkinitcpio.conf; then
        # MODULES=() の場合と MODULES=(既存) の場合を分けて処理
        if grep -q '^MODULES=()' /mnt/etc/mkinitcpio.conf; then
          sed -i 's/^MODULES=()/MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)/' /mnt/etc/mkinitcpio.conf
        else
          sed -i 's/^MODULES=(\(.*\))/MODULES=(\1 nvidia nvidia_modeset nvidia_uvm nvidia_drm)/' /mnt/etc/mkinitcpio.conf
        fi
      fi
    "
    # MODULES に nvidia を入れた場合、HOOKS の kms は外す。
    # kms が残っていると initramfs に nouveau が同梱され、早期 KMS で
    # プロプライエタリドライバと競合して黒画面になることがある（Arch Wiki 推奨）。
    run_cmd "mkinitcpio.conf から kms フックを除去 (NVIDIA)" bash -c "
      sed -i '/^HOOKS=/ s/\bkms[[:space:]]*//' /mnt/etc/mkinitcpio.conf
    "
    # nouveau をモジュールレベルでも無効化（KMS 競合の二重防止）
    run_cmd "nouveau のブラックリスト設定" bash -c "
      mkdir -p /mnt/etc/modprobe.d
      echo 'blacklist nouveau' > /mnt/etc/modprobe.d/nvidia-blacklist-nouveau.conf
    "
  fi

  # 各種サービスの有効化

  if [[ "${CONFIG[extra_ssh]}" == "yes" ]]; then
    run_cmd "OpenSSH サービス有効化" systemctl --root=/mnt enable sshd
  fi

  if [[ "${CONFIG[extra_fstrim]:-no}" == "yes" ]]; then
    run_cmd "fstrim.timer 有効化（SSD 定期 TRIM）" systemctl --root=/mnt enable fstrim.timer
  fi

  if [[ "${CONFIG[extra_ufw]}" == "yes" ]]; then
    # SSH を併用する場合はロックアウト防止のため 22 番ポートを事前許可
    if [[ "${CONFIG[extra_ssh]}" == "yes" ]]; then
      run_cmd "ufw: SSH(22) を許可" arch-chroot /mnt ufw allow ssh
    fi
    run_cmd "UFW サービス有効化" systemctl --root=/mnt enable ufw
    # systemctl enable だけではファイアウォールは有効にならない
    # （ufw.service は起動時に /etc/ufw/ufw.conf の ENABLED を参照する）。
    # chroot 内で「ufw enable」は実行できないため、設定ファイルを直接書き換える。
    run_cmd "ufw 有効化フラグ設定 (ENABLED=yes)" bash -c "
      if grep -q '^ENABLED=' /mnt/etc/ufw/ufw.conf 2>/dev/null; then
        sed -i 's/^ENABLED=.*/ENABLED=yes/' /mnt/etc/ufw/ufw.conf
      else
        echo 'ENABLED=yes' >> /mnt/etc/ufw/ufw.conf
      fi
    "
  fi

  case "${CONFIG[virt_env]}" in
    oracle)
      run_cmd "VirtualBox Guest サービス有効化" systemctl --root=/mnt enable vboxservice
      ;;
    kvm|qemu)
      run_cmd "QEMU Guest Agent 有効化" systemctl --root=/mnt enable qemu-guest-agent
      ;;
    vmware)
      run_cmd "VMware Tools サービス有効化" systemctl --root=/mnt enable vmtoolsd
      ;;
  esac

  # xdg-user-dirs-update の自動実行設定（初回ログイン時にホームディレクトリ群を生成）
  # 選択されたシェルのプロファイルにのみ追記する
  run_cmd "fish スケルディレクトリ作成" mkdir -p ${SKEL_ROOT}/.config/fish

  # bash が選ばれている場合のみ .bash_profile に追記
  if echo "${CONFIG[users]}" | grep -q '|bash|'; then
    run_cmd "bash xdg-user-dirs-update 設定" bash -c "cat >> ${SKEL_ROOT}/.bash_profile << 'EOF'

# 初回ログイン時にユーザーディレクトリを自動作成
if [ -x /usr/bin/xdg-user-dirs-update ]; then
  xdg-user-dirs-update
fi
EOF"
  fi

  # zsh が選ばれている場合のみ .zprofile に追記
  if echo "${CONFIG[users]}" | grep -q '|zsh|'; then
    run_cmd "zsh xdg-user-dirs-update 設定" bash -c "cat >> ${SKEL_ROOT}/.zprofile << 'EOF'

# 初回ログイン時にユーザーディレクトリを自動作成
if [ -x /usr/bin/xdg-user-dirs-update ]; then
  xdg-user-dirs-update
fi
EOF"
  fi

  # fish が選ばれている場合のみ config.fish に追記
  if echo "${CONFIG[users]}" | grep -q '|fish|'; then
    run_cmd "fish xdg-user-dirs-update 設定" bash -c "cat >> ${SKEL_ROOT}/.config/fish/config.fish << 'EOF'

# 初回ログイン時にユーザーディレクトリを自動作成
if test -x /usr/bin/xdg-user-dirs-update
  xdg-user-dirs-update
end
EOF"
  fi

  # ── starship プロンプトの初期化 ──
  # 【重要】do_desktop ではなくここで行うこと。以前は Hyprland / Niri のときだけ
  # 設定していたため、GNOME や KDE、CLI のみの構成では starship を入れても
  # プロンプトが素のままで、「入れたのに何も変わらない」状態だった。
  # starship.toml を置くだけでは何も起きず、シェルの rc で init を呼んで初めて効く。
  #
  # 【重要】.bash_profile ではなく .bashrc に書くこと。プロンプトは対話シェルごとに
  # 必要で、ログインシェルでしか読まれない profile に置くと端末を開き直すたびに
  # 素のプロンプトへ戻る。
  # 【重要】コマンドの存在を確認してから eval すること。starship が入っていない
  # 環境でこの行が走ると、シェル起動のたびに command not found が表示される。
  # 【注意】heredoc は必ず << 'EOF'（クォート付き）で書くこと。
  # 本文の $(starship init ...) はインストール先のシェルが実行時に評価する式であり、
  # ここで展開されてはいけない。run_cmd + bash -c "..." で包むと二重クォートの
  # エスケープが絡んで壊れやすいため、他の設定生成と同じく直接 heredoc で書き出す。
  if echo "${CONFIG[users]}" | grep -q '|bash|'; then
    cat >> ${SKEL_ROOT}/.bashrc << 'EOF'

# starship プロンプト（設定: ~/.config/starship.toml）
if command -v starship > /dev/null 2>&1; then
  eval "$(starship init bash)"
fi
EOF
    print_ok "bash: starship プロンプトを設定しました"
  fi
  if echo "${CONFIG[users]}" | grep -q '|zsh|'; then
    cat >> ${SKEL_ROOT}/.zshrc << 'EOF'

# starship プロンプト（設定: ~/.config/starship.toml）
if command -v starship > /dev/null 2>&1; then
  eval "$(starship init zsh)"
fi
EOF
    print_ok "zsh: starship プロンプトを設定しました"
  fi
  if echo "${CONFIG[users]}" | grep -q '|fish|'; then
    cat >> ${SKEL_ROOT}/.config/fish/config.fish << 'EOF'

# starship プロンプト（設定: ~/.config/starship.toml）
if type -q starship
    starship init fish | source
end
EOF
    print_ok "fish: starship プロンプトを設定しました"
  fi

  # Chromium / Electron 系アプリの Wayland / IME 連携設定
  run_cmd "Chromium/Electron 向け Wayland IME 連携設定" bash -c "
    mkdir -p ${SKEL_ROOT}/.config
    cat > ${SKEL_ROOT}/.config/chrome-flags.conf << 'EOF'
--ozone-platform-hint=auto
--enable-wayland-ime
EOF
    cp ${SKEL_ROOT}/.config/chrome-flags.conf ${SKEL_ROOT}/.config/chromium-flags.conf
    cp ${SKEL_ROOT}/.config/chrome-flags.conf ${SKEL_ROOT}/.config/electron-flags.conf
    cp ${SKEL_ROOT}/.config/chrome-flags.conf ${SKEL_ROOT}/.config/code-flags.conf
  "

  # OS 名・バナーの書き込み
  write_os_branding

  # initramfs の再生成。
  # 【重要】mkinitcpio.conf を書き換えたときだけ行うこと。
  # pacstrap の linux 導入時に既に生成されており（vconsole.conf も先に置いてある）、
  # 何も変えていないのに作り直すと、fallback を含めて数十秒を無駄にする。
  # 逆に mkinitcpio.conf を変えるコードを足したら、必ず initramfs_dirty を立てること。
  if [[ "$initramfs_dirty" == "yes" ]]; then
    run_cmd "initramfs 再生成 (mkinitcpio)" arch-chroot /mnt mkinitcpio -P
  else
    print_ok "initramfs: pacstrap 時に生成済みのものを使用（設定変更なしのため再生成を省略）"
  fi
}

# ============================================
# 実行: ユーザー設定
# ============================================

do_users() {
  print_step "ユーザー設定"

  local entry
  while IFS= read -r entry; do
    [[ -z "$entry" ]] && continue
    parse_users_line "$entry"

    local shell_path="/bin/bash"
    case "$ushell" in
      zsh)  shell_path="/bin/zsh" ;;
      fish) shell_path="/bin/fish" ;;
    esac

    run_cmd "ユーザー作成: ${uname}" \
      arch-chroot /mnt useradd -m -G "$ugroups" -s "$shell_path" "$uname"

    _set_password "$uname" "$upw"
    upw=""  # メモリ上の平文パスワードをクリア

    if [[ "$usudo" == "yes" ]]; then
      run_cmd "sudo 設定: ${uname}" bash -c "
        echo '${uname} ALL=(ALL:ALL) ALL' > /mnt/etc/sudoers.d/${uname}
        chmod 0440 /mnt/etc/sudoers.d/${uname}
      "
    elif [[ "$usudo" == "nopasswd" ]]; then
      run_cmd "sudo 設定: ${uname} (NOPASSWD)" bash -c "
        echo '${uname} ALL=(ALL:ALL) NOPASSWD: ALL' > /mnt/etc/sudoers.d/${uname}
        chmod 0440 /mnt/etc/sudoers.d/${uname}
      "
    fi
  done <<< "${CONFIG[users]}"

  # 【重要】ループ内の upw="" はローカル変数を消しているだけで、
  # CONFIG[users] には全ユーザーの平文パスワードが入ったまま残る。
  # 以降で users を参照するのは「ユーザー名の一覧」だけなので、
  # パスワード欄を空にした形に詰め直しておく。
  local _sanitized="" _e
  while IFS= read -r _e; do
    [[ -z "$_e" ]] && continue
    parse_users_line "$_e"
    if [[ -z "$_sanitized" ]]; then
      _sanitized="${uname}||${usudo}|${ushell}|${ugroups}"
    else
      _sanitized="${_sanitized}
${uname}||${usudo}|${ushell}|${ugroups}"
    fi
  done <<< "${CONFIG[users]}"
  CONFIG[users]="$_sanitized"
  upw=""

  # root パスワード
  # 【注意】この分岐は「root パスワードの有無」で判定している。
  # 一般ユーザーの有無とは別の話なので、メッセージを取り違えないこと。
  if [[ -n "${CONFIG[root_password]}" ]]; then
    _set_password "root" "${CONFIG[root_password]}"
    CONFIG[root_password]=""  # メモリ上の平文パスワードをクリア
    print_ok "root パスワードを設定しました。"
  else
    print_warn "root パスワードが未設定です。root では直接ログインできません。"
  fi

  if [[ "${CONFIG[users_count]:-0}" -eq 0 ]]; then
    print_warn "一般ユーザーが作成されていません。root アカウントのみになります。"
  fi
}
do_bootloader() {
  print_step "ブートローダーのインストール"

  local disk="${CONFIG[disk]}"
  local scheme="${CONFIG[partition_scheme]}"
  local root_part
  local swap_part=""
  local swap_partuuid=""

  # do_format_and_mount で確定済みならそれを使う（manual でも再質問しない）。
  # ここで CONFIG を信頼することで、resume フック（do_chroot_config）と
  # resume= カーネルパラメータが必ず同じ swap を指すようになる。
  if [[ -n "${CONFIG[root_part]}" ]]; then
    root_part="${CONFIG[root_part]}"
    swap_part="${CONFIG[swap_part]}"
    print_ok "パーティション: root=${root_part}${swap_part:+ / swap=${swap_part}}"
  elif [[ "$scheme" == "manual" ]]; then
    # 手動パーティション時はパーティション番号が不定なのでユーザーに確認
    print_warn "手動パーティションモードのため、ブートローダー用にパーティションを確認します。"
    lsblk -p "$disk" 2>/dev/null || fdisk -l "$disk" 2>/dev/null || ls "/sys/block/${disk#/dev/}/" || true
    while true; do
      root_part=$(ask "Root (/) パーティションのデバイスパス（例: /dev/sda2）")
      [[ -b "$root_part" ]] && break
      print_err "有効なブロックデバイスではありません: $root_part"
    done

    # manual 時も swap の有無をユーザーに確認する
    local swap_input
    swap_input=$(ask "Swap パーティションのデバイスパス（不要なら空 Enter）" "")
    if [[ -n "$swap_input" ]]; then
      if [[ -b "$swap_input" ]]; then
        swap_part="$swap_input"
      else
        print_warn "有効なデバイスではないため swap はスキップします: $swap_input"
      fi
    fi
  elif [[ "$scheme" == "auto_swap" ]]; then
    swap_part=$(part_suffix "$disk" 2)
    root_part=$(part_suffix "$disk" 3)
  else
    root_part=$(part_suffix "$disk" 2)
  fi

  # swap_partuuid 取得 — scheme に関わらず swap_part が設定されていれば取得する
  if [[ -n "$swap_part" ]]; then
    if [[ "${CONFIG[dry_run]}" != "yes" ]]; then
      swap_partuuid=$(blkid -s PARTUUID -o value "$swap_part" || echo "")
    else
      swap_partuuid="DRY-RUN-SWAP-PARTUUID"
    fi
  fi

  # 追加ブートオプション作成
  local extra_options=""
  if [[ -n "$swap_partuuid" ]]; then
    extra_options+=" resume=PARTUUID=${swap_partuuid}"
  fi
  if [[ "${CONFIG[gpu_driver]}" == "nvidia" ]]; then
    extra_options+=" nvidia-drm.modeset=1"
  fi

  # btrfs はルートを subvol=@ でマウントしているため、カーネルに rootflags を渡す。
  # これが無いと initramfs がトップレベルボリューム（@ や @home が並ぶ階層）を
  # ルートとしてマウントし、init が見つからず起動に失敗する。
  # （GRUB は grub-mkconfig が自動で付与するため systemd-boot のみ明示する）
  local sb_rootflags=""
  [[ "${CONFIG[fs_type]:-ext4}" == "btrfs" ]] && sb_rootflags=" rootflags=subvol=@"

  if [[ "${CONFIG[bootloader]}" == "systemd-boot" ]]; then
    # bootctl インストール
    run_cmd "bootctl インストール" arch-chroot /mnt bootctl install

    # ローダー設定
    # 起動メニューの待ち時間。Linux だけのディスクでは毎回の起動を待たせるだけなので
    # 1 秒にする（その間に矢印キーを押せばメニューで止まり、fallback も選べる）。
    # Windows があるときは選ぶ時間が要るので従来どおり 5 秒。
    local loader_timeout=1
    [[ "${CONFIG[windows_found]:-no}" == "yes" ]] && loader_timeout=5
    run_cmd "loader.conf 作成" bash -c "cat > /mnt/boot/loader/loader.conf << EOF
default  arch.conf
timeout  ${loader_timeout}
console-mode max
editor   no
EOF"

    local root_partuuid
    if [[ "${CONFIG[dry_run]}" != "yes" ]]; then
      root_partuuid=$(blkid -s PARTUUID -o value "$root_part")
      if [[ -z "$root_partuuid" ]]; then
        print_err "root パーティション ($root_part) の PARTUUID を取得できませんでした。"
        print_err "パーティションが正しくフォーマットされているか確認してください。"
        exit 1
      fi
    else
      root_partuuid="DRY-RUN-ROOT-PARTUUID"
    fi

    # マイクロコードの initrd を判定
    local ucode_initrd=""
    local cpu_vendor="${CONFIG[cpu_vendor]}"
    if [[ "$cpu_vendor" == "GenuineIntel" ]]; then
      ucode_initrd="initrd  /intel-ucode.img"
    elif [[ "$cpu_vendor" == "AuthenticAMD" ]]; then
      ucode_initrd="initrd  /amd-ucode.img"
    fi

    # エントリファイル作成（ucode が空の場合は空行を入れない）
    local ucode_line=""
    [[ -n "$ucode_initrd" ]] && ucode_line="${ucode_initrd}"$'\n'
    run_cmd "arch.conf エントリ作成" bash -c "mkdir -p /mnt/boot/loader/entries && cat > /mnt/boot/loader/entries/arch.conf << EOF
title   Arch Linux
linux   /vmlinuz-linux
${ucode_line}initrd  /initramfs-linux.img
options root=PARTUUID=${root_partuuid}${sb_rootflags} rw quiet${extra_options}
EOF"

    # フォールバックエントリ
    run_cmd "arch-fallback.conf 作成" bash -c "cat > /mnt/boot/loader/entries/arch-fallback.conf << EOF
title   Arch Linux (fallback)
linux   /vmlinuz-linux
${ucode_line}initrd  /initramfs-linux-fallback.img
options root=PARTUUID=${root_partuuid}${sb_rootflags} rw${extra_options}
EOF"

    # pacman フック（カーネル更新時に自動更新）
    run_cmd "systemd-boot 自動更新フック設定" \
      systemctl --root=/mnt enable systemd-boot-update.service

  else
    # GRUB
    if [[ "${CONFIG[boot_mode]}" == "uefi" ]]; then
      run_cmd "GRUB インストール (UEFI)" \
        arch-chroot /mnt grub-install \
          --target=x86_64-efi \
          --efi-directory=/boot \
          --bootloader-id=GRUB
    else
      run_cmd "GRUB インストール (BIOS)" \
        arch-chroot /mnt grub-install \
          --target=i386-pc \
          "${CONFIG[disk]}"
    fi

    # GRUB 向けに追加パラメータを設定
    if [[ -n "$extra_options" ]]; then
      # 先頭スペースを除去してから挿入（CMDLINE が空のとき " resume=..." にならないよう）
      local extra_options_trimmed="${extra_options# }"
      run_cmd "GRUB 設定ファイルにパラメータを追加" bash -c "
        if [[ -f /mnt/etc/default/grub ]]; then
          sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT=\"\(.*\)\"/GRUB_CMDLINE_LINUX_DEFAULT=\"\1 ${extra_options_trimmed}\"/' /mnt/etc/default/grub
          # CMDLINE が空だった場合の先頭スペースを除去
          sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT=\" /GRUB_CMDLINE_LINUX_DEFAULT=\"/' /mnt/etc/default/grub
        fi
      "
    fi

    # Windows 等の他OSを検出してGRUBメニューに追加（os-prober を有効化）
    if [[ "${CONFIG[windows_found]}" == "yes" ]]; then
      run_cmd "GRUB os-prober 有効化（他OS検出）" bash -c "
        if [[ -f /mnt/etc/default/grub ]]; then
          if grep -q '^#\?GRUB_DISABLE_OS_PROBER' /mnt/etc/default/grub; then
            sed -i 's/^#\?GRUB_DISABLE_OS_PROBER=.*/GRUB_DISABLE_OS_PROBER=false/' /mnt/etc/default/grub
          else
            echo 'GRUB_DISABLE_OS_PROBER=false' >> /mnt/etc/default/grub
          fi
        fi
      "
      print_ok "os-prober 有効化: Windows があればメニューに自動追加されます"
    fi

    run_cmd "grub.cfg 生成" \
      arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg
  fi
}

# 任意の git リポジトリを clone → makepkg -si する（ユーザー権限・ホーム内・単一セッション）。
# 成功=0 / 失敗=1（非致命的）。呼び出し側で一時 NOPASSWD sudo を用意しておくこと。
# 引数: 1=ユーザー名 2=git URL 3=クローン先ディレクトリ名 4=表示ラベル（省略時は3）
_makepkg_git_install() {
  local user="$1" giturl="$2" dir="$3" label="${4:-$3}"
  run_cmd_soft "${label} のビルド & インストール（ユーザー: ${user}）" \
    arch-chroot /mnt sudo -u "${user}" -H bash -c '
      set -e
      # 隠しディレクトリを使い、ホーム直下に見えるフォルダを残さない
      bd="$HOME/.cache/aur-build"; mkdir -p "$bd"; cd "$bd"
      for i in 1 2 3; do
        rm -rf "'"${dir}"'"
        git clone --depth=1 "'"${giturl}"'" "'"${dir}"'" && break
        echo "git clone に失敗、リトライ ($i/3)"; sleep 5
        [ "$i" = 3 ] && exit 1
      done
      cd "'"${dir}"'"
      makepkg -si --noconfirm --needed
      # ビルドディレクトリと、空になった作業用の親ディレクトリを削除する
      cd "$HOME"; rm -rf "$bd/'"${dir}"'"
      rmdir "$bd" 2>/dev/null || true
    '
}

# AUR パッケージ1つをビルド&インストール（_makepkg_git_install の AUR 版ラッパー）。
# 引数1: ユーザー名, 引数2: AUR リポジトリ名（=パッケージ名）
_aur_makepkg_install() {
  local user="$1" repo="$2"
  _makepkg_git_install "$user" "https://aur.archlinux.org/${repo}.git" "$repo" "$repo"
}

# AUR/Chrome が入らなかった場合の手動導入手順を表示
_aur_manual_hint() {
  local helper="$1"
  print_warn "後から手動で導入する場合（再起動後、一般ユーザーで実行）:"
  echo -e "    ${GRAY}sudo pacman -S --needed git base-devel${RESET}"
  if [[ "${CONFIG[install_chrome]:-no}" == "yes" ]]; then
    echo -e "    ${GRAY}git clone https://aur.archlinux.org/google-chrome.git${RESET}"
    echo -e "    ${GRAY}cd google-chrome && makepkg -si${RESET}"
  fi
  if [[ "$helper" != "none" ]]; then
    local repo="$helper"; [[ "$helper" == "yay" ]] && repo="yay-bin"
    echo -e "    ${GRAY}git clone https://aur.archlinux.org/${repo}.git && cd ${repo} && makepkg -si${RESET}"
  fi
  if [[ "${CONFIG[install_ytfzf]:-no}" == "yes" ]]; then
    echo -e "    ${GRAY}git clone https://github.com/yannsi/yt-fzf-sh && cd yt-fzf-sh && makepkg -si${RESET}"
  fi
}

do_aur_helper() {
  local helper="${CONFIG[aur_helper]}"
  local want_chrome="${CONFIG[install_chrome]:-no}"
  local want_ytfzf="${CONFIG[install_ytfzf]:-no}"


  # いずれも不要ならスキップ
  [[ "$helper" == "none" && "$want_chrome" != "yes" && "$want_ytfzf" != "yes" ]] && return

  # STEP_TOTAL に計上済みのため、スキップ時もステップ表示を先に行う
  print_step "追加パッケージのインストール（AUR ヘルパー / Chrome / yt-fzf / 電源メニュー）"

  # 代表ユーザー名を取得（CONFIG[users] の最初のユーザー）
  local first_user
  first_user=$(cut -d'|' -f1 <<< "$(head -n1 <<< "${CONFIG[users]}")")
  if [[ -z "$first_user" ]]; then
    print_warn "一般ユーザーが登録されていないため、追加パッケージのインストールをスキップします。"
    return
  fi

  # ドライランのときはスキップ
  if [[ "${CONFIG[dry_run]}" == "yes" ]]; then
    print_warn "ドライランのため AUR 関連をスキップします"
    return
  fi

  # chroot 内の AUR 接続確認（AUR/Chrome 用。yt-fzf は GitHub なので clone 時に個別判定）
  local aur_ok="yes"
  if [[ "$helper" != "none" || "$want_chrome" == "yes" ]]; then
    echo -ne "  ${CYAN}…${RESET} chroot 内の AUR 接続を確認中..."
    if arch-chroot /mnt git ls-remote "https://aur.archlinux.org/google-chrome.git" &>/dev/null; then
      echo -e "\r  ${GREEN}✔${RESET} chroot 内の AUR 接続OK"
    else
      aur_ok="no"
      echo -e "\r  ${YELLOW}⚠${RESET} chroot 内で AUR に接続できません — AUR/Chrome はスキップします"
      print_warn "DNS（/etc/resolv.conf）の同期不良などが原因の可能性があります。"
      _aur_manual_hint "$helper"
    fi
  fi

  # makepkg は root で実行できないため、非対話ビルド用に一時的な NOPASSWD sudo を付与。
  # 重要: sudoers.d は「ファイル名の辞書順」に読まれ、同一ユーザーでは後勝ち。
  # do_users がユーザー名（例 taro＝パスワードあり）でファイルを作るため、
  # 数字始まりの名前（例 99-...）だと taro より前に読まれ、上書きされて無効化される。
  # そこで「ユーザー名＋接尾辞」の名前にし、必ず当該ユーザーのファイルより後に読ませる。
  local temp_sudoers="/etc/sudoers.d/${first_user}-aur-nopasswd"
  # 異常終了時に trap（_cleanup_temp_sudoers）が消せるようグローバルにも控える
  AUR_TEMP_SUDOERS="$temp_sudoers"
  run_cmd "一時的な sudo NOPASSWD 設定の追加" bash -c "
    echo '${first_user} ALL=(ALL:ALL) NOPASSWD: ALL' > /mnt${temp_sudoers}
    chmod 0440 /mnt${temp_sudoers}
  "

  # ── 1) AUR ヘルパー（任意）──
  if [[ "$helper" != "none" && "$aur_ok" == "yes" ]]; then
    local repo_name="$helper"
    [[ "$helper" == "yay" ]] && repo_name="yay-bin"
    if _aur_makepkg_install "$first_user" "$repo_name"; then
      print_ok "${helper} をインストールしました（今後の AUR は「${helper} -S <名前>」で導入可）"
    else
      print_warn "${helper} のインストールに失敗しました（スキップして継続）"
    fi
  fi

  # ── 2) Google Chrome（yay に依存せず AUR から直接ビルド）──
  # google-chrome の依存は公式リポジトリのみのため、makepkg -si 単体で完結する。
  if [[ "$want_chrome" == "yes" && "$aur_ok" == "yes" ]]; then
    if _aur_makepkg_install "$first_user" "google-chrome"; then
      print_ok "Google Chrome をインストールしました"
    else
      print_warn "Google Chrome のインストールに失敗しました（後から makepkg で導入できます）"
    fi
  fi

  # ── 3) yt-fzf-sh（GitHub の PKGBUILD から直接ビルド）──
  # fzf/yt-dlp を使う対話的 YouTube ダウンローダ/再生ツール。
  # 依存(fzf, yt-dlp, mpv, ffmpeg)は makepkg -si が公式リポジトリから自動導入する。
  if [[ "$want_ytfzf" == "yes" ]]; then
    if _makepkg_git_install "$first_user" \
         "https://github.com/yannsi/yt-fzf-sh" "yt-fzf-sh" "yt-fzf-sh (YouTube ツール)"; then
      print_ok "yt-fzf-sh をインストールしました（コマンド: ${BOLD}yt-fzf${RESET}）"
      # クリップボード連携(PKGBUILD の optdepend)。
      # COSMIC は Wayland セッションなので wl-clipboard。
      run_cmd_soft "wl-clipboard 導入（yt-fzf のクリップボード連携）" \
        arch-chroot /mnt pacman -S --noconfirm --needed wl-clipboard || true
    else
      print_warn "yt-fzf-sh のインストールに失敗しました（後から手動で導入できます）"
    fi
  fi

  # 一時的な sudo 設定を削除
  run_cmd "一時的な sudo NOPASSWD 設定の削除" rm -f "/mnt${temp_sudoers}"
  AUR_TEMP_SUDOERS=""
}

# COSMIC 用の日本語フォント設定を /etc/skel に配置する。
# COSMIC のシェルは cosmic-text（独自フォントDB）で描画し、fontconfig の
# locale ベース match ルールを読まない。既定の Open Sans / Noto Sans Mono には
# 日本語グリフが無く、フォールバックで漢字が中国語字形(SC)になるため、
# COSMIC 自身の設定でシステム/等幅フォントを JP 付きファミリに固定する。
# 設定形式は libcosmic の CosmicTk(version=1) に準拠（各項目が個別ファイル・RON）。
write_cosmic_font_config() {
  [[ "${CONFIG[dry_run]}" == "yes" ]] && return 0
  local tk_dir="${SKEL_ROOT}/.config/cosmic/com.system76.CosmicTk/v1"
  run_cmd "COSMIC 日本語フォント設定を配置" bash -c "mkdir -p '$tk_dir' && \
cat > '$tk_dir/interface_font' << 'EOF'
(
    family: \"Noto Sans CJK JP\",
    weight: Normal,
    stretch: Normal,
    style: Normal,
)
EOF
cat > '$tk_dir/monospace_font' << 'EOF'
(
    family: \"Noto Sans Mono CJK JP\",
    weight: Normal,
    stretch: Normal,
    style: Normal,
)
EOF"
  print_ok "COSMIC: システム/等幅フォントを日本語字形(JP)に固定しました"

  # COSMIC のアプリはそれぞれ独自のフォント設定を持ち、既定は "Noto Sans Mono"
  # （日本語グリフ無し）。CosmicTk を直しても各アプリには波及しないため、
  # 個別に font_name を JP 付き等幅ファミリへ固定する。
  # font_name は String 型なので、中身は引用符付きの RON 文字列 1 行。
  # 対象: テキストエディタ(CosmicEdit) / ターミナル(CosmicTerm)、いずれも v1。
  local app
  for app in CosmicEdit CosmicTerm; do
    local app_dir="${SKEL_ROOT}/.config/cosmic/com.system76.${app}/v1"
    run_cmd "COSMIC ${app} フォント設定を配置" bash -c \
      "mkdir -p '$app_dir' && printf '%s' '\"Noto Sans Mono CJK JP\"' > '$app_dir/font_name'"
  done
  print_ok "COSMIC: エディタ・ターミナルのフォントを日本語字形(JP)に固定しました"
}

# coffee版: COSMIC の既定ターミナル（Super+T 等のシステムショートカット）を
# ghostty に固定する。
#
# 【重要】/usr/share/cosmic/com.system76.CosmicSettings.Shortcuts/v1/system_actions
# には絶対に書かないこと（cosmic-settings-daemon パッケージ所有のファイル）。
# cosmic-settings-daemon は「システム側のファイルを丸ごと土台にし、
# ユーザー側のファイルの項目で上書きする（extend）」という読み方をする。
# かつてシステム側を Terminal の1行だけで上書きしていたため、土台にあった
# ランチャー・アプリライブラリ・スクリーンショット・音量/輝度キー・Alt+Tab・
# 画面ロックなどの割り当てがすべて消えていた。しかもパッケージ更新のたびに
# 元のファイルへ戻るため、「直ったり壊れたりする」分かりにくい壊れ方をする。
# ユーザー側は差分だけ書けばよいので、Terminal の1行で ghostty になる。
write_cosmic_terminal_config() {
  [[ "${CONFIG[dry_run]}" == "yes" ]] && return 0
  local dir="${SKEL_ROOT}/.config/cosmic/com.system76.CosmicSettings.Shortcuts/v1"
  mkdir -p "$dir" || return 0
  printf '{\n    Terminal: "/usr/bin/ghostty",\n}\n' > "${dir}/system_actions"
}

# COSMIC のドック固定アプリ（App List の favorites）を /etc/skel に焼き込む。
#
# 【重要】COSMIC のドックは ~/.config/cosmic/com.system76.CosmicAppList/v1/favorites
# だけを見る。ここに何も書かないと、Firefox や Chrome をインストールしても
# ドックには一切並ばない（COSMIC 既定の Files / Terminal / Store 等のみ）。
# 実機で「パネルに firefox・chrome が出ない」となったのがこれ。
#
# 【経緯】以前はホストPCの ~/.config/cosmic を丸ごとコピーする経路にだけ
# 頼っていた。しかし Live ISO から起動すると _host_home はホストを見つけられず
# GitHub の dotfiles にフォールバックし、そちらは niri 環境なので
# .config/cosmic を持たない。結果コピーのループが -d 判定で素通りし、
# favorites が誰にも書かれないまま終わっていた。
#
# 【重要】実体のない .desktop の ID を書くと空アイコンが並ぶだけになるため、
# インストール先に .desktop が存在するものだけを採用する。
write_cosmic_favorites() {
  [[ "${CONFIG[dry_run]}" == "yes" ]] && return 0

  local dir="${SKEL_ROOT}/.config/cosmic/com.system76.CosmicAppList/v1"
  local f="${dir}/favorites"

  # ホストPCから引き継いだ favorites があれば、そちらを尊重して触らない。
  [[ -s "$f" ]] && { print_ok "COSMIC: ドックの固定アプリは引き継ぎ元の設定を使用します"; return 0; }

  # 並べたい順。ブラウザ → ターミナル → ファイル → オフィス → 設定。
  local candidates=(
    firefox
    google-chrome
    com.mitchellh.ghostty
    com.system76.CosmicTerm
    com.system76.CosmicFiles
    libreoffice-startcenter
    com.system76.CosmicSettings
  )

  local ids=() id
  for id in "${candidates[@]}"; do
    [[ -f "/mnt/usr/share/applications/${id}.desktop" ]] && ids+=("$id")
  done
  [[ "${#ids[@]}" -eq 0 ]] && { print_warn "COSMIC: 固定できるアプリが見つからず、ドックは既定のままになります"; return 0; }

  mkdir -p "$dir" || return 0
  # 書式は RON の文字列配列。
  {
    printf '[\n'
    printf '    "%s",\n' "${ids[@]}"
    printf ']\n'
  } > "$f"
  print_ok "COSMIC: ドックの固定アプリを設定しました (${ids[*]})"
}

# COSMIC 上での LibreOffice メニュー無反応の回避。
# LibreOffice の各ランチャー(.desktop)を /etc/skel にコピーし、Exec 行に
# 「env SAL_USE_VCLPLUGIN=gtk3 GDK_BACKEND=x11」を前置した上書き版を置く。
# ・SAL_USE_VCLPLUGIN=gtk3 : gtk3 系 VCL プラグインを使う
# ・GDK_BACKEND=x11        : gtk3 を XWayland 経由で動かし popup 不具合を回避
# GDK_BACKEND は他の GTK アプリに影響しないよう、全体設定にはせず
# LibreOffice のランチャーだけに閉じ込める。install_office=yes のときのみ実行。
write_libreoffice_cosmic_launchers() {
  [[ "${CONFIG[dry_run]}" == "yes" ]] && return 0
  [[ "${CONFIG[install_office]:-no}" == "yes" ]] || return 0
  run_cmd "COSMIC: LibreOffice ランチャーを XWayland 経由に上書き" bash -c '
    shopt -s nullglob
    dst=${SKEL_ROOT}/.local/share/applications
    mkdir -p "$dst"
    found=0
    for f in /mnt/usr/share/applications/libreoffice-*.desktop; do
      sed "s|^Exec=|Exec=env SAL_USE_VCLPLUGIN=gtk3 GDK_BACKEND=x11 |" \
        "$f" > "$dst/$(basename "$f")"
      found=1
    done
    [ "$found" -eq 1 ]
  ' || print_warn "LibreOffice の .desktop が見つからず、ランチャー上書きをスキップしました"
}



# ============================================
# 実行: デスクトップ環境
# ============================================

do_desktop() {
  # STEP_TOTAL に計上済みのため、スキップ時もステップ表示を先に行う
  # （早期 return より前に print_step しないと [n/N] の番号がずれる）
  print_step "デスクトップ環境のインストール: COSMIC"

  # dry_run 時は /mnt がマウントされていないためスキップ
  if [[ "${CONFIG[dry_run]}" == "yes" ]]; then
    print_warn "ドライランのためデスクトップ環境のセットアップをスキップします"
    return 0
  fi

  # pipewire-jack と jack2 の競合を事前に回避
  if arch-chroot /mnt pacman -Qi jack2 &>/dev/null; then
    run_cmd "jack2 の一時削除 (pipewire-jack 競合回避)" \
      arch-chroot /mnt pacman -Rdd --noconfirm jack2
  fi

  # 音声・Bluetooth・ファイルシステム・マルチメディア・ブラウザなどのデスクトップ共通パッケージ
  local desktop_common_pkgs=(
    pipewire pipewire-pulse wireplumber
    pipewire-alsa pipewire-jack libldac
    bluez bluez-utils
    cups cups-pdf avahi nss-mdns system-config-printer
    xdg-user-dirs xdg-utils
    firefox
    # ファイルシステムツール（ntfs-3g / exfatprogs 等）は do_pacstrap で導入済み。
    # ここには GUI 側だけを置く。
    #
    # 【重要】スマートフォン接続は Android と iPhone で必要なものが異なる。
    # ・Android は MTP を使うので gvfs-mtp でよい。
    # ・iPhone は MTP を話さず、Apple 独自の AFC と PTP を使う。
    #   写真・動画は gvfs-gphoto2 (PTP)、アプリのドキュメント領域は
    #   gvfs-afc が担当するので、両方入れないと中身が見えない。
    # 以前は gvfs-mtp しか無く、iPhone を挿しても何も表示されなかった。
    #
    # gvfs-afc は libimobiledevice と usbmuxd を依存に持つため、
    # この2つは自動で入る（明示指定は不要）。
    # ifuse は公式リポジトリでの提供状況が変わりうるので、ここには含めない。
    # gvfs 経由でファイルマネージャから開ければ通常の用途は足りる。
    gvfs gvfs-mtp gvfs-smb gvfs-afc gvfs-gphoto2
    gnome-disk-utility udisks2
    gst-plugins-good gst-libav
    libdvdcss libdvdread libdvdnav
    # 【重要】mpv は DE を問わずここで入れること。
    # 以前は Hyprland / Niri の pkgs にしか入れておらず、GNOME・KDE・Xfce・
    # Budgie・COSMIC には動画プレイヤーが一つも入らない状態だった。
    # 一方でコーデック(gst-libav / libdvd*)は全DEに入れており、
    # さらに do_desktop 末尾で ~/.config/mpv を全DEの skel に複製している。
    # 「設定だけあって本体が無い」ちぐはぐな状態になるため共通側に置く。
    mpv
    # streamlink / yt-dlp / sox / imagemagick / qrencode は do_pacstrap へ移動。
    # desktop=none（CLI のみ）でも入るようにするため。
    # ここに書き戻すと、その構成にだけ入らない状態に逆戻りする。
  )

  # ── トランザクション統合 ──
  # SDDM と推奨アプリを COSMIC 本体と同一の pacman 実行にまとめ、
  # 依存解決とフォントキャッシュ再生成などのフック実行の重複を減らす（時間短縮）
  desktop_common_pkgs+=(sddm)

  # 初心者向け推奨アプリ（unzip/git 等の軽量ツール。LibreOffice は選択制）
  desktop_common_pkgs+=(unzip p7zip wget curl git nano htop)
  # LibreOffice 本体 + 日本語言語パック(-ja)。本体だけだと UI が英語のままなので、
  # ロケールが日本語でも -ja を入れて初めて UI が日本語になる。
  if [[ "${CONFIG[install_office]:-no}" == "yes" ]]; then
    desktop_common_pkgs+=(libreoffice-fresh)
    [[ "${CONFIG[japanese_env]}" == "yes" ]] && desktop_common_pkgs+=(libreoffice-fresh-ja)
  fi
  # 【重要】firefox 本体も明示して入れること。
  # firefox-i18n-ja は firefox を依存に持つので本体自体は入るが、依存として
  # 入るだけだと pacman -Qdt に孤児候補として並び、言語パックを消すと本体まで
  # 一緒に消える。明示インストールにしておけば独立して残る。
  [[ "${CONFIG[japanese_env]}" == "yes" ]] && desktop_common_pkgs+=(firefox firefox-i18n-ja)

  # ── COSMIC 本体 ──
  # coffee版: 既定ターミナルを ghostty に一本化するため、cosmic 本体と
  # 一緒に導入する（cosmic-term はグループの依存関係として残るが、
  # ショートカット/パネルからは ghostty を使うよう下で明示的に設定する）。
  local pkgs=(cosmic ghostty)
  run_cmd_retry "COSMIC インストール" \
    arch-chroot /mnt pacman -S --noconfirm --needed "${pkgs[@]}" "${desktop_common_pkgs[@]}"
  # COSMIC のシェル(cosmic-text)は /etc/fonts/conf.d の locale ルールを読まず、
  # 既定フォント（Open Sans / Noto Sans Mono）に日本語グリフが無いため、
  # 漢字がフォールバックで中国語字形(SC)になる。COSMIC 自身の設定
  # （com.system76.CosmicTk v1）でシステム/等幅フォントを JP 付きファミリに
  # 直接指定して回避する。noto-fonts-cjk は step_fonts で導入済み。
  write_cosmic_font_config

  # ドックの固定アプリ。ここで先に書いておき、ホストPCの ~/.config/cosmic を
  # 引き継ぐ場合は後段のコピーがこれを上書きする（＝ホスト優先）。
  # 引き継がない場合はここで書いたものがそのまま残る。
  write_cosmic_favorites
  # coffee版: COSMIC の既定ターミナル（Super+T 等のシステムショートカット）を
  # ghostty に設定する。ユーザー設定側だけに書く（理由は
  # write_cosmic_terminal_config のコメント参照）。
  write_cosmic_terminal_config
  # COSMIC のコンポジタ上では LibreOffice の gtk3 プラグインがネイティブ
  # Wayland だとメニューのポップアップを出せない（クリックしても開かない）。
  # gtk3 のまま XWayland 経由（GDK_BACKEND=x11）で動かすと回避できるため、
  # LibreOffice のランチャーだけに env を差し込む上書き .desktop を生成する。
  write_libreoffice_cosmic_launchers

  # ── 壁紙 ──
  # COSMIC 自身が壁紙を描画するので、ここは「既定値をどこに書くか」だけの話。
  local de_wall
  de_wall=$(_install_wallpaper)
  if [[ -n "$de_wall" ]]; then
    _set_de_wallpaper "$de_wall"
  else
    print_warn "壁紙画像を取得できなかったため、壁紙は COSMIC 既定のままにします"
  fi

  # 推奨アプリ（unzip/git/LibreOffice 等）はデスクトップ本体と
  # 同一トランザクションで導入済み（desktop_common_pkgs 参照）

  # デスクトップ用共通サービス（Bluetooth, CUPS, Avahi）有効化
  run_cmd "Bluetooth サービス有効化" systemctl --root=/mnt enable bluetooth
  run_cmd "CUPS (印刷) サービス有効化" systemctl --root=/mnt enable cups
  run_cmd "Avahi (ネットワーク探索) サービス有効化" systemctl --root=/mnt enable avahi-daemon
  run_cmd "ローカルホスト名解決 (nss-mdns) の設定" sed -i '/^hosts:/ s/ \(resolve\|dns\)/ mdns_minimal [NOTFOUND=return] \1/' /mnt/etc/nsswitch.conf

  # ホストPCの各種アプリ設定をターゲットの /etc/skel にコピー
  if [[ "${CONFIG[dry_run]}" != "yes" ]]; then
    local host_home host_config_dir=""
    host_home=$(_host_home)
    [[ -n "$host_home" ]] && host_config_dir="${host_home}/.config"

    if [[ -d "$host_config_dir" ]]; then
      mkdir -p ${SKEL_ROOT}/.config

      # 【重要】「設定をコピーする対象」は「本体を導入する対象」と揃えること。
      # 本体の無い設定だけがホームに残ると、「~/.config にあるのに動かない」
      # 原因の分かりにくいゴミになる。
      #
      # cosmic: パネル/ドック配置・テーマ・固定アプリ・既定ターミナルなどは
      #         ~/.config/cosmic 配下に一括りで入っている（アプリごとに
      #         分かれた個別ディレクトリではない）ため 1エントリでまるごと
      #         コピーし、壁紙とディスプレイ構成だけ後段で個別に除外する。
      local app_configs=(mpv cosmic)

      # 日本語入力の設定は DE に依存しないため、日本語環境なら常に引き継ぐ。
      # fcitx5 側に変換キー・句読点・キーバインドの設定が、mozc 側にユーザー辞書と
      # 学習履歴が入っている。ここを複製しないと「同じ操作感」にはならない。
      if [[ "${CONFIG[japanese_env]}" == "yes" && "${CONFIG[jp_ime]:-none}" =~ ^fcitx5 ]]; then
        app_configs+=(fcitx5 mozc)
      fi

      # 【重要】cp -a ではなく cp -aL（リンクを辿る）を使うこと。
      # dotfiles を git 管理して ~/.config/<app> からシンボリックリンクを張る運用では、
      # -a のままだと次の2つの壊れ方をする:
      #   1. リンク自体が複製され、インストール先には存在しないパスを指す
      #      リンク切れになる（エラーは出ず、設定だけが黙って既定に戻る）。
      #   2. コピー先に同名ディレクトリが既にある場合（alacritty がまさにそう。
      #      上の「alacritty フォント設定」で先に生成される）、cp は
      #      "cannot overwrite directory with non-directory" で失敗する。
      #      run_cmd は失敗で exit 1 するため、インストール全体が停止する。
      # -L なら実体がコピーされ、既存ディレクトリへはマージ（同名ファイルは上書き）される。
      for app in "${app_configs[@]}"; do
        if [[ -d "$host_config_dir/$app" ]]; then
          run_cmd "ホストPCから ${app} 設定をコピー" cp -aL "$host_config_dir/$app" ${SKEL_ROOT}/.config/
        fi
      done

      # coffee版: COSMIC の壁紙設定（com.system76.CosmicBackground /
      # com.system76.CosmicSettings.Wallpaper）だけは上のコピーから除外する。
      # coffee版は壁紙を GitHub の coffee 画像に統一する方針（config_source の
      # 選択と無関係）なので、ホストの壁紙設定を残すとユーザー設定が
      # システム既定より優先されてしまい、coffee 版の壁紙が出なくなる。
      if [[ "${CONFIG[desktop]}" == "cosmic" ]]; then
        rm -rf "${SKEL_ROOT}/.config/cosmic/com.system76.CosmicBackground" \
               "${SKEL_ROOT}/.config/cosmic/com.system76.CosmicSettings.Wallpaper"
        # 【順序注意】ホストの ~/.config/cosmic には（ホスト自身の）
        # 日本語フォント設定も含まれるため通常は上と矛盾しないが、
        # 将来ホスト側の設定が変わっても文字化けを再発させないよう、
        # コピー後に必ず上書きし直して JP フォントを保証する。
        write_cosmic_font_config

        # 【順序注意】上の rm でこちらが用意した壁紙設定も一緒に消えるため、
        # ここで書き直す。coffee 版は「壁紙は常に coffee」の方針なので、
        # ホスト側の壁紙設定を引き継がずこちらを最終的な値にする。
        write_cosmic_wallpaper_config

        # 【重要】ディスプレイ構成はマシン固有なので引き継がない。
        # cosmic-comp は出力の解像度・リフレッシュレート・スケール・配置を
        # 出力名（eDP-1 / DP-3 など）付きで保持している。別のマシンや別の
        # モニタ構成に持ち込むと、存在しない出力に対する設定が残って
        # 画面が出ない・スケールがおかしいといった形で効いてくる。
        # 名前は COSMIC の版によって揺れるため output で始まるものをまとめて落とす。
        rm -f "${SKEL_ROOT}/.config/cosmic/com.system76.CosmicComp/v1/"output* 2>/dev/null || true

        # ホスト側に favorites が無かった場合（niri 環境の dotfiles を
        # 引き継いだときなど）に備えて、ここでも書き直しておく。
        # 既にファイルがあれば write_cosmic_favorites 側で何もしない。
        write_cosmic_favorites

        # 既定ターミナルも同様に、ホスト設定で消えていれば書き直す。
        write_cosmic_terminal_config
      fi

      # ディレクトリではなく単体ファイルで置かれる設定（starship.toml 等）。
      # 上のループは -d 判定のため素通りしてしまうので個別に扱う。
      # starship は全インストール共通で導入するため、設定も DE を問わず引き継ぐ。
      local file_configs=(starship.toml)
      for f in "${file_configs[@]}"; do
        if [[ -f "$host_config_dir/$f" ]]; then
          run_cmd "ホストPCから ${f} をコピー" cp -aL "$host_config_dir/$f" ${SKEL_ROOT}/.config/
        fi
      done

      # 【順序注意】starship.toml をコピーした直後に呼ぶこと。
      # 置換対象は skel 上のファイルなので、コピー前に走らせても何も起きない。
      _strip_esca_glyph
      _fix_starship_nerdfont_v3

      # テーマを試した残骸（*.bak / *.bak_cyberpunk / *_bak）を配布前に落とす。
      # 設定ファイル本体と紛らわしく、どれが本番か分からなくなるため。
      run_cmd_soft "複製した設定のバックアップファイルを除去" \
        find ${SKEL_ROOT}/.config -type f \( -name '*.bak' -o -name '*.bak_*' -o -name '*_bak' -o -name '*.bak.*' \) -delete || true
    fi
  fi

  # 各一般ユーザーのホームディレクトリに /etc/skel の内容（デスクトップ設定含む）をコピー
  _sync_skel_to_homes
}

# ============================================
# ユーティリティ: /etc/skel を各ユーザーのホームへ配る
# ============================================
# do_desktop の末尾から呼ばれる。
# cp -a の上書きなので、複数回呼んでも結果は変わらない（冪等）。
_sync_skel_to_homes() {
  [[ "${CONFIG[dry_run]}" == "yes" ]] && return 0

  local entry uname upw usudo ushell ugroups
  while IFS= read -r entry; do
    [[ -z "$entry" ]] && continue
    parse_users_line "$entry"
    [[ -d "/mnt/home/$uname" ]] || continue

    # 【重要】chown は必ず chroot 内で実行する。
    # ユーザーは chroot 内の useradd で作成されるため、ホスト（Live ISO）の
    # passwd DB には存在せず、ホスト側 chown は "invalid spec" で失敗する。
    run_cmd "ユーザー設定ファイルの同期: ${uname}" bash -c "
      cp -a ${SKEL_ROOT}/. /mnt/home/${uname}/
      arch-chroot /mnt chown -R ${uname}: /home/${uname}
    "
    # 【重要】arch-chroot は chroot に直接 exec するためシェルビルトインを渡せない。
    # 「arch-chroot /mnt command -v ...」は常に失敗するので、実体の有無で判定する。
    if [[ -x /mnt/usr/bin/xdg-user-dirs-update ]]; then
      run_cmd "ユーザーディレクトリ初期作成: ${uname}" \
        arch-chroot /mnt bash -c "
          HOME=/home/${uname} \
          LANG=${CONFIG[locale]} \
          XDG_CONFIG_HOME=/home/${uname}/.config \
          xdg-user-dirs-update --force
          chown -R ${uname}: /home/${uname}
        "
    fi

  done <<< "${CONFIG[users]}"
}
# ============================================
# SDDM テーマ「Esca」の書き込み
# ============================================
# テーマ一式をヒアドキュメントで直接書き出す。
#
#
# 【設計】QtQuick.Controls を使っていない。スタイルプラグインが無い環境では
# 描画されず「ログイン画面が真っ白」になり、TTY からの復旧が必要になる。
#
# ヒアドキュメントは全て 'クォート付き' にしてある。QML 内の $ や ` を
# シェルに解釈させないため。
write_sddm_theme() {
  local theme_dir="/mnt/usr/share/sddm/themes/esca"

  if [[ "${CONFIG[dry_run]}" == "yes" ]]; then
    print_warn "SDDM テーマの書き込み (ドライラン - スキップ)"
    return 0
  fi

  mkdir -p "$theme_dir"

  # SDDM 背景画像を用意する。スクリプト同梱 → GitHub の順で探し、
  # 見つからなければ何もしない。Main.qml 側は Image が読み込めなくても
  # 下地のグラデーション（テーマ色）がそのまま見えるだけなので、
  # この画像が無くても画面が壊れることはない。画像を持たないテーマは
  # グラデーションだけのログイン画面になる。
  #
  # 【重要】取得成否を必ずログに出すこと。ここが無言で失敗すると、
  # 実機で「ログイン画面に画像が出ない」という現象だけが残り、
  # 原因（ネットワーク不通／取得先の変更／破損ファイル）が追えなくなる。
  local sddm_bg_src=""
  if [[ -f "${SCRIPT_DIR}/${THEME_SDDM_LOCAL}" ]]; then
    sddm_bg_src="${SCRIPT_DIR}/${THEME_SDDM_LOCAL}"
  else
    # JPEG のマジックバイト（\xFF\xD8）で検証する。_fetch_cached はサイズ
    # 512バイト以上という緩い足切りしかしないため、これが無いと取得先が
    # HTML のエラーページ等にすり替わっていても「成功」扱いになりかねない。
    sddm_bg_src=$(_fetch_cached "/tmp/esca-sddm-${THEME}-bg.jpg" \
      "https://raw.githubusercontent.com/${ESCA_DOTFILES_REPO#https://github.com/}/${ESCA_DOTFILES_BRANCH}/${THEME_SDDM_REMOTE}" \
      "$(printf '\xFF\xD8')")
  fi
  if [[ -n "$sddm_bg_src" ]] && cp "$sddm_bg_src" "${theme_dir}/background.jpg" 2>/dev/null; then
    chmod 644 "${theme_dir}/background.jpg" 2>/dev/null || true
    print_ok "SDDM 背景画像（${THEME_LABEL}）を設置しました: ${sddm_bg_src}"
  else
    print_warn "SDDM 背景画像（${THEME_LABEL}）が用意されていません。ログイン画面はグラデーションのみになります"
  fi

  cat > "${theme_dir}/Main.qml" <<'ESCA_MAIN_QML_EOF'
// Esca Linux — SDDM テーマ
//
// 【方針1】QtQuick.Controls を使わず QtQuick だけで組む。
//   Controls はスタイルプラグインが環境に無いと描画されず、
//   「ログイン画面が真っ白で操作できない」＝復旧が面倒な事態になる。
//   Rectangle と TextInput で自前に描けば QtQuick だけで完結する。
//
// 【方針2】import を 2.15 表記にする。Qt5.15 / Qt6 のどちらでも解釈できる。
//
// 【方針3】アイコンフォントを使わず日本語ラベルで書く。
//   ログイン画面はフォント設定が効く前なので、豆腐（□）になると詰む。

import QtQuick 2.15

Rectangle {
    id: root

    width: 1920
    height: 1080
    color: "@@SEA_DEEP@@"

    // ---- 配色 ----
    // 値は write_sddm_theme が選択中のテーマから流し込む（@@SEA_DEEP@@ 等を sed で置換）。
    // ヒアドキュメントは 'クォート付き' で QML 内の $ を守る必要があるため、
    // シェル変数の展開ではなく置換マーカー方式にしている。
    readonly property color seaDeep:  "@@SEA_DEEP@@"
    readonly property color seaMid:   "@@SEA_MID@@"
    readonly property color seaLight: "@@SEA_LIGHT@@"
    readonly property color rodLight: "@@ROD_LIGHT@@"
    readonly property color glowGold: "@@GLOW_GOLD@@"
    readonly property color textMain: "@@TEXT_MAIN@@"
    readonly property color textDim:  "@@TEXT_DIM@@"
    readonly property color errorRed: "#ff8b7a"

    property int    sessionIndex: sessionModel.lastIndex
    property string errorText: ""
    property string currentSessionName: ""

    // theme.conf の値。未設定でも動くよう既定値を用意する。
    // 日本語が豆腐になるのを避けるため CJK フォントを既定にしている。
    readonly property string uiFont: (typeof config !== "undefined" && config.font) ? config.font : "Noto Sans CJK JP"
    // 下部ボタンの表示。theme.conf の showSessionButton / showPowerButtons を
    // false にすると隠れる。値は文字列で来るため "false" との比較で判定する。
    readonly property bool showSession: !(typeof config !== "undefined" && String(config.showSessionButton) === "false")
    readonly property bool showPower:   !(typeof config !== "undefined" && String(config.showPowerButtons) === "false")

    // ============================================
    // 背景
    // ============================================
    // 下地はテーマ色のグラデーション。write_sddm_theme が用意できた場合のみ
    // 上に背景画像を重ねる。画像が無い/読み込めない場合でも
    // Image は何も描かず、下地のグラデーションがそのまま見えるだけなので、
    // 画面が壊れる（真っ黒・操作不能になる）ことはない。
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0;  color: root.seaLight }
            GradientStop { position: 0.55; color: root.seaMid }
            GradientStop { position: 1.0;  color: root.seaDeep }
        }
    }

    Image {
        anchors.fill: parent
        source: "background.jpg"
        fillMode: Image.PreserveAspectCrop
        smooth: true
        asynchronous: true
        cache: false
    }

    // ログイン欄の可読性を保つための暗めのオーバーレイ
    Rectangle {
        anchors.fill: parent
        color: "#000000"
        opacity: 0.32
    }

    // ============================================
    // 時計（右上）
    // ============================================
    Column {
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 48
        spacing: 4

        Text {
            id: clockTime
            anchors.right: parent.right
            color: root.textMain
            font.pixelSize: 52
            font.family: root.uiFont
            font.weight: Font.Light
            text: Qt.formatDateTime(new Date(), "HH:mm")
        }
        Text {
            id: clockDate
            anchors.right: parent.right
            color: root.textDim
            font.family: root.uiFont
            font.pixelSize: 17
            text: Qt.formatDateTime(new Date(), "yyyy年M月d日 dddd")
        }
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: {
            var now = new Date()
            clockTime.text = Qt.formatDateTime(now, "HH:mm")
            clockDate.text = Qt.formatDateTime(now, "yyyy年M月d日 dddd")
        }
    }

    // ============================================
    // 中央: ロゴとログインフォーム
    // ============================================
    Column {
        id: loginColumn
        anchors.centerIn: parent
        spacing: 20
        width: 380

        // ロゴ（あんこうの発光アイコン）は表示しない。
        // 背景のコーヒーカップのイラスト自体がロゴの役割を兼ねるため。
        // 初代テーマのロゴ（発光するあんこう）はここでは表示しない
        // （未使用のまま theme_dir に残るだけで、動作に影響はない）。

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            // テーマ名は write_sddm_theme が流し込む（例: Esca Linux Coffee）
            text: "@@TITLE@@"
            color: root.textMain
            font.pixelSize: 26
            font.family: root.uiFont
            font.letterSpacing: 3
        }

        Item { width: 1; height: 12 }

        InputField {
            id: userField
            width: parent.width
            placeholder: "ユーザー名"
            text: userModel.lastUser
            accentColor: root.rodLight
            textColor: root.textMain
            hintColor: root.textDim
            onAccepted: passField.forceFocus()
        }

        InputField {
            id: passField
            width: parent.width
            placeholder: "パスワード"
            echoMode: TextInput.Password
            accentColor: root.rodLight
            textColor: root.textMain
            hintColor: root.textDim
            onAccepted: root.doLogin()
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.errorText
            color: root.errorRed
            font.pixelSize: 14
            visible: root.errorText !== ""
        }

        TextButton {
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width
            label: "ログイン"
            primary: true
            accentColor: root.rodLight
            onClicked: root.doLogin()
        }
    }

    // ============================================
    // 下部左: セッション選択
    // ============================================
    TextButton {
        id: sessionButton
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.margins: 36
        // 一覧から選ぶまでは SDDM が覚えている前回のセッションが使われる
        label: "セッション: " + (root.currentSessionName !== "" ? root.currentSessionName : "前回と同じ")
        textColor: root.textMain
        visible: root.showSession
        onClicked: sessionPopup.visible = !sessionPopup.visible
    }

    // ============================================
    // 下部右: 電源操作
    // ============================================
    Row {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 36
        spacing: 12
        visible: root.showPower

        TextButton {
            label: "スリープ"
            textColor: root.textMain
            visible: sddm.canSuspend
            onClicked: sddm.suspend()
        }
        TextButton {
            label: "再起動"
            textColor: root.textMain
            visible: sddm.canReboot
            onClicked: sddm.reboot()
        }
        TextButton {
            label: "シャットダウン"
            textColor: root.textMain
            visible: sddm.canPowerOff
            onClicked: sddm.powerOff()
        }
    }

    // セッション一覧。ボタンの真上に出す
    Rectangle {
        id: sessionPopup
        visible: false
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.leftMargin: 36
        anchors.bottomMargin: 88
        width: 300
        height: Math.min(sessionList.count * 40 + 12, 320)
        radius: 6
        color: "@@SEA_MID@@"
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.14)

        ListView {
            id: sessionList
            anchors.fill: parent
            anchors.margins: 6
            clip: true
            model: sessionModel
            delegate: Rectangle {
                id: sessionRow
                required property int index
                required property string name
                width: sessionList.width - 12
                height: 40
                radius: 4
                color: hover.containsMouse ? Qt.rgba(1, 1, 1, 0.10) : "transparent"

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.leftMargin: 12
                    text: sessionRow.name
                    color: root.textMain
                    font.pixelSize: 14
                }

                MouseArea {
                    id: hover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.sessionIndex = sessionRow.index
                        root.currentSessionName = sessionRow.name
                        sessionPopup.visible = false
                    }
                }
            }
        }
    }

    // ============================================
    // ログイン処理
    // ============================================
    function doLogin() {
        root.errorText = ""
        if (userField.text.length === 0) {
            root.errorText = "ユーザー名を入力してください"
            return
        }
        sddm.login(userField.text, passField.text, root.sessionIndex)
    }

    Connections {
        target: sddm

        function onLoginFailed() {
            root.errorText = "ユーザー名またはパスワードが違います"
            passField.text = ""
            passField.forceFocus()
        }

        function onLoginSucceeded() {
            root.errorText = ""
        }
    }

    // 起動直後にフォーカスを合わせる。
    // ユーザー名が既に入っていればパスワード欄から始めるのが自然。
    Component.onCompleted: {
        if (userField.text.length > 0) {
            passField.forceFocus()
        } else {
            userField.forceFocus()
        }
    }
}
ESCA_MAIN_QML_EOF

  cat > "${theme_dir}/InputField.qml" <<'ESCA_INPUTFIELD_QML_EOF'
// 入力欄の共通部品（ユーザー名・パスワードで使い回す）
//
// 【重要】枠の半透明に opacity を使わないこと。
// opacity は子に継承されるため、中の文字まで薄くなって読めなくなる。
// Qt.rgba() で色そのものにアルファを持たせれば、文字は不透明のまま。

import QtQuick 2.15

Rectangle {
    id: field

    property alias text: input.text
    property alias echoMode: input.echoMode
    property string placeholder: ""
    property color textColor: "@@TEXT_MAIN@@"
    property color hintColor: "@@TEXT_DIM@@"
    property color accentColor: "@@ROD_LIGHT@@"

    signal accepted()

    height: 48
    radius: 6
    color: Qt.rgba(1, 1, 1, 0.08)
    border.width: input.activeFocus ? 2 : 1
    border.color: input.activeFocus ? accentColor : Qt.rgba(1, 1, 1, 0.14)

    Behavior on border.color {
        ColorAnimation { duration: 120 }
    }

    TextInput {
        id: input
        anchors.fill: parent
        anchors.leftMargin: 16
        anchors.rightMargin: 16
        verticalAlignment: TextInput.AlignVCenter
        color: field.textColor
        font.pixelSize: 16
        selectByMouse: true
        selectionColor: field.accentColor
        selectedTextColor: "@@SEA_DEEP@@"
        clip: true
        onAccepted: field.accepted()
    }

    Text {
        anchors.left: parent.left
        anchors.leftMargin: 16
        anchors.verticalCenter: parent.verticalCenter
        text: field.placeholder
        color: field.hintColor
        font.pixelSize: 16
        visible: input.text.length === 0 && !input.activeFocus
    }

    function forceFocus() {
        input.forceActiveFocus()
    }
}
ESCA_INPUTFIELD_QML_EOF

  cat > "${theme_dir}/TextButton.qml" <<'ESCA_TEXTBUTTON_QML_EOF'
// 文字ラベルのボタン。電源操作・セッション選択・ログインで使う。
//
// アイコンフォントに依存すると環境によって豆腐（□）になるため、
// ラベルは日本語テキストで書く。ログイン画面で読めないのは致命的。

import QtQuick 2.15

Rectangle {
    id: button

    property string label: ""
    property bool primary: false
    property color accentColor: "@@ROD_LIGHT@@"
    property color textColor: "@@TEXT_MAIN@@"

    signal clicked()

    implicitWidth: labelText.implicitWidth + 40
    implicitHeight: 40
    radius: 6

    color: {
        if (primary) {
            return mouse.pressed ? Qt.darker(accentColor, 1.25)
                 : mouse.containsMouse ? Qt.lighter(accentColor, 1.1)
                 : accentColor
        }
        return mouse.pressed ? Qt.rgba(1, 1, 1, 0.20)
             : mouse.containsMouse ? Qt.rgba(1, 1, 1, 0.13)
             : Qt.rgba(1, 1, 1, 0.06)
    }

    border.width: primary ? 0 : 1
    border.color: Qt.rgba(1, 1, 1, 0.12)

    Behavior on color {
        ColorAnimation { duration: 100 }
    }

    Text {
        id: labelText
        anchors.centerIn: parent
        text: button.label
        color: button.primary ? "@@SEA_DEEP@@" : button.textColor
        font.pixelSize: 15
        font.bold: button.primary
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: button.clicked()
    }
}
ESCA_TEXTBUTTON_QML_EOF

  cat > "${theme_dir}/theme.conf" <<'ESCA_THEME_CONF_EOF'
[General]
# ログイン画面で使うフォント。
# 日本語が豆腐（□）になるのを避けるため CJK 対応フォントを既定にする。
# ここを空にすると Qt の既定フォントになる。
font=Noto Sans CJK JP


# 下部のボタン表示。false にすると隠れる。
showSessionButton=true
showPowerButtons=true
ESCA_THEME_CONF_EOF

  cat > "${theme_dir}/metadata.desktop" <<'ESCA_METADATA_DESKTOP_EOF'
[SddmGreeterTheme]
Name=Esca
Description=Esca Linux 公式テーマ — 深海と発光する esca
Author=Esca Linux
Copyright=Esca Linux
License=MIT
Type=sddm-theme
# 【必須】Qt のバージョンを宣言する。
# これが無いと、Qt6 環境でも SDDM が正しいグリーターを選べず、
# 既定テーマへフォールバックもせずに真っ黒な画面になる。
# Arch の SDDM は Qt6 のため 6 を指定する。
QtVersion=6
Version=1.0
Website=@OS_HOME_URL@
MainScript=Main.qml
ConfigFile=theme.conf
TranslationsDirectory=
Email=
ESCA_METADATA_DESKTOP_EOF

  # 【重要】上のヒアドキュメントはデリミタを 'ESCA_METADATA_DESKTOP_EOF' と
  # クォートしているため、中では変数が一切展開されない（設定値を literal で
  # 書くために意図的にそうしている）。よって URL は @OS_HOME_URL@ という
  # プレースホルダで置き、ここで置換する。
  # 直接 ${OS_HOME_URL} と書くと、その文字列がそのままファイルに残る。
  sed -i "s|@OS_HOME_URL@|${OS_HOME_URL}|g" "${theme_dir}/metadata.desktop"

  # 配色の流し込み。QML のヒアドキュメントも同じ理由でクォートしてあるため、
  # @@SEA_DEEP@@ 等のマーカーを選択中のテーマの色に置換する。
  #
  # 【重要】部品側（InputField.qml / TextButton.qml）も必ず対象に含めること。
  # かつてここは Main.qml だけを差し替えており、部品のプロパティ既定値と
  # 文字選択色・ボタン文字色は初代テーマの青がハードコードされたまま残っていた。
  # Main.qml から色を渡している箇所は上書きされるので大半は見えないが、
  # 文字を選択したときとボタンを押したときだけ配色から外れた紺が覗いていた。
  local qml
  for qml in Main.qml InputField.qml TextButton.qml; do
    [[ -f "${theme_dir}/${qml}" ]] || continue
    sed -i \
      -e "s|@@SEA_DEEP@@|${THEME_SEA_DEEP}|g" \
      -e "s|@@SEA_MID@@|${THEME_SEA_MID}|g" \
      -e "s|@@SEA_LIGHT@@|${THEME_SEA_LIGHT}|g" \
      -e "s|@@ROD_LIGHT@@|${THEME_ROD_LIGHT}|g" \
      -e "s|@@GLOW_GOLD@@|${THEME_GLOW_GOLD}|g" \
      -e "s|@@TEXT_MAIN@@|${THEME_TEXT_MAIN}|g" \
      -e "s|@@TEXT_DIM@@|${THEME_TEXT_DIM}|g" \
      -e "s|@@TITLE@@|${OS_NAME} ${THEME^}|g" \
      "${theme_dir}/${qml}"
  done

  # 置換漏れがあれば QML は色名として解釈できず、その要素が黒で描かれる。
  # 見た目が崩れるだけでエラーにならないため、ここで検出して知らせる。
  #
  # 【重要】検査対象は QML だけに限ること。テーマディレクトリには背景 JPEG も
  # 置くため、ディレクトリごと grep すると画像のバイト列にたまたま "@@" が
  # 含まれて必ず警告が出る（実際に coffee で誤検出した）。
  if grep -ql '@@' "${theme_dir}"/*.qml 2>/dev/null; then
    print_warn "SDDM テーマに未置換のマーカーが残っています（配色が崩れる可能性があります）"
  fi

  # テーマを有効化する。既存の設定を壊さないよう専用ファイルに書く。
  mkdir -p /mnt/etc/sddm.conf.d
  cat > /mnt/etc/sddm.conf.d/10-theme.conf <<'ESCA_SDDM_CONF_EOF'
# Esca Linux のログインテーマ指定。
# 画面が出ずログインできない場合は、TTY (Ctrl+Alt+F2) からこのファイルを
# 削除して sddm を再起動すれば既定のテーマに戻る。
#   sudo rm /etc/sddm.conf.d/10-theme.conf && sudo systemctl restart sddm
[Theme]
Current=esca
ESCA_SDDM_CONF_EOF

  print_ok "SDDM テーマ「Esca」を配置しました（配色: ${THEME_LABEL}）"
}

do_display_manager() {
  print_step "ログイン画面のセットアップ: SDDM"

  # sddm 本体は do_desktop の desktop_common_pkgs で COSMIC と同一
  # トランザクションで導入済み。ここは有効化とテーマ配置だけ。
  # --needed が効くので、万一入っていなくてもこの行で入る。
  run_cmd_retry "SDDM インストール" \
    arch-chroot /mnt pacman -S --noconfirm --needed sddm
  run_cmd "SDDM 有効化" systemctl --root=/mnt enable sddm
  write_sddm_theme
}

# （完了画面の案内は再起動後に消えるため、ファイルとして残す）
write_first_login_guide() {
  [[ "${CONFIG[dry_run]}" == "yes" ]] && return 0
  [[ -z "${CONFIG[users]}" ]] && return 0

  local guide_tmp="/tmp/myarch_guide_$$.txt"
  {
    echo "========================================"
    echo " はじめにお読みください（Esca Linux ・ ${THEME_LABEL}）"
    echo "========================================"
    echo ""
    if [[ "${CONFIG[jp_ime]:-none}" =~ ^fcitx5 ]]; then
      echo "■ 日本語入力"
      echo "  ・オン/オフ切り替え: Ctrl + Space（または 半角/全角 キー）"
      echo "  ・切り替わらない場合は一度ログアウト → 再ログイン"
      echo "  ・うまく動かないときの診断: fcitx5-diagnose"
      echo ""
    fi
    echo "■ システムの更新"
    echo "  ・公式パッケージの更新: sudo pacman -Syu"
    if [[ "${CONFIG[aur_helper]:-none}" != "none" ]]; then
      echo "  ・AUR を含む更新     : yay -Syu"
      echo "  ・パッケージの検索   : yay -Ss キーワード"
      echo "  ・インストール       : yay -S パッケージ名"
    fi
    echo ""
    echo "■ AUR アプリを git で手動更新する方法"
    if [[ "${CONFIG[aur_helper]:-none}" != "none" ]]; then
      echo "  ※ yay を導入済みなら「yay -Syu」だけで AUR アプリ"
      if [[ "${CONFIG[install_chrome]:-no}" == "yes" ]]; then
        echo "    （Google Chrome 含む）もまとめて更新されます。"
      else
        echo "    もまとめて更新されます。"
      fi
      echo "    以下は yay を使わずに更新したい場合の手順です。"
    fi
    echo "  1. AUR からビルドファイルを取得（例: Google Chrome）"
    echo "       git clone https://aur.archlinux.org/google-chrome.git"
    echo "  2. ビルドしてインストール"
    echo "       cd google-chrome"
    echo "       makepkg -si"
    echo "  3. 片付け（ビルドファイルは残しておく必要はありません）"
    echo "       cd .. && rm -rf google-chrome"
    echo "  ※ 他の AUR パッケージも同じ手順です:"
    echo "     https://aur.archlinux.org/パッケージ名.git を clone → makepkg -si"
    if [[ "${CONFIG[install_ytfzf]:-no}" == "yes" ]]; then
      echo ""
      echo "  【注意】yt-fzf は GitHub 由来のため yay -Syu では更新されません。"
      echo "  更新するには同じ git 手順で再ビルドしてください:"
      echo "       git clone --depth=1 https://github.com/yannsi/yt-fzf-sh"
      echo "       cd yt-fzf-sh && makepkg -si"
      echo "       cd .. && rm -rf yt-fzf-sh"
    fi
    echo ""
    echo "■ プロンプト（starship）"
    echo "  ・設定ファイル: ~/.config/starship.toml"
    echo "  ・変更後は端末を開き直すと反映されます。"
    echo "  ・プリセット一覧と適用方法: starship preset --list"
    echo "  ・元の素のプロンプトに戻したい場合は、シェルの rc"
    echo "    （~/.bashrc / ~/.zshrc / ~/.config/fish/config.fish）末尾の"
    echo "    starship の行を削除してください。"
    echo ""
    echo "■ コンソール（TTY）フォント"
    echo "  ・設定ファイル: /etc/vconsole.conf（既定は FONT=ter-116n）"
    echo "  ・小さすぎる場合は大きいサイズに変更できます:"
    echo "       sudo sed -i 's/^FONT=.*/FONT=ter-124n/' /etc/vconsole.conf"
    echo "       sudo mkinitcpio -P     # 起動直後から反映させる場合"
    echo "  ・すぐ試すだけなら: setfont ter-124n"
    echo "  ・利用できるサイズ: ls /usr/share/kbd/consolefonts/ | grep '^ter-'"
    echo "  ※ TTY では Nerd Font のアイコンは表示できません（PSF の制約）。"
    echo "    starship の記号が崩れる場合は次で切り替えられます:"
    echo "       starship preset plain-text-symbols -o ~/.config/starship.toml"
    echo ""
    echo "■ 壁紙"
    echo "  ・既定の壁紙: ${WALLPAPER_DEST}"
    echo "  ・変更するには 設定 → 外観 → 壁紙 から選びます。"
    echo "  ・設定画面が使えない場合は、次のファイルの source 行を"
    echo "    使いたい画像の絶対パスに書き換えてください（保存すると即反映）:"
    echo "       ~/.config/cosmic/com.system76.CosmicBackground/v1/all"
    echo "  ※ COSMIC は「このファイルが指す1枚」だけを見ます。"
    echo "    画像をディレクトリに置くだけでは切り替わりません。"
    echo "  ・プロジェクトのページ:"
    echo "       ${OS_HOME_URL}"
    echo ""
    echo "■ COSMIC の設定について"
    echo "  ・既定のターミナルは ghostty です（Super + T）。"
    echo "    変更する場合は次のファイルの中身を書き換えます:"
    echo "       ~/.config/cosmic/com.system76.CosmicSettings.Shortcuts/v1/system_actions"
    echo "  ・ドックに固定するアプリは右クリックの「App Tray に固定」で増減できます。"
    echo "    直接編集する場合はこちら（.desktop ファイル名から .desktop を除いた ID）:"
    echo "       ~/.config/cosmic/com.system76.CosmicAppList/v1/favorites"
    echo "  ・日本語が中国語の字形で表示される場合は、フォント設定が"
    echo "    上書きされた可能性があります。次の3つを確認してください:"
    echo "       ~/.config/cosmic/com.system76.CosmicTk/v1/interface_font"
    echo "       ~/.config/cosmic/com.system76.CosmicEdit/v1/font_name"
    echo "       ~/.config/cosmic/com.system76.CosmicTerm/v1/font_name"
    echo ""
    echo "■ ログインできなくなったときは"
    echo "  1. Ctrl + Alt + F2 で文字だけの画面（TTY）に切り替え、"
    echo "     同じユーザー名とパスワードでログインします。"
    echo "     ここで入れるならアカウントは無事で、原因はデスクトップ側です。"
    echo "     （デスクトップに戻るときは Ctrl + Alt + F1）"
    echo "  2. 古いセッションが残っていないか確認します:"
    echo "       loginctl list-sessions"
    echo "     残っていれば終了させます:  loginctl terminate-session <ID>"
    echo "  3. ログイン画面を作り直します:"
    echo "       sudo systemctl restart sddm"
    echo "  4. それでも駄目なら、原因はログに残っています:"
    echo "       journalctl -b -u sddm --no-pager | tail -50"
    echo "       journalctl -b --user -u cosmic-session --no-pager | tail -50"
    echo "  ・デスクトップの設定が壊れて起動しない場合、設定を退避すれば"
    echo "    初期状態で入り直せます（元に戻したいときは名前を戻すだけ）:"
    echo "       mv ~/.config/cosmic ~/.config/cosmic.bak"
    echo ""
    echo "■ ミラーが遅くなったら"
    echo "  sudo reflector --country Japan --protocol https --age 24 \\"
    echo "    --sort rate --number 8 --save /etc/pacman.d/mirrorlist"
    echo ""
    echo "■ 困ったときは"
    echo "  ・インストール時のログ: /var/log/$(basename "${CONFIG[log_file]}")"
    echo "  ・ArchWiki 日本語版   : https://wiki.archlinux.jp/"
    echo ""
    echo "（このファイルは不要になったら削除して構いません）"
  } > "$guide_tmp"

  local entry uname upw usudo ushell ugroups
  while IFS= read -r entry; do
    [[ -z "$entry" ]] && continue
    parse_users_line "$entry"
    [[ -d "/mnt/home/${uname}" ]] || continue
    cp "$guide_tmp" "/mnt/home/${uname}/はじめにお読みください.txt"
    arch-chroot /mnt chown "${uname}:" "/home/${uname}/はじめにお読みください.txt" 2>/dev/null || true
  done <<< "${CONFIG[users]}"
  rm -f "$guide_tmp"
  print_ok "初回ログインガイドを各ユーザーのホームに作成しました"
}

do_cleanup() {
  print_step "後処理"

  # AUR ビルドの残骸フォルダを掃除（万一ビルドが途中で失敗した場合の保険）。
  # 各ユーザーのホーム直下 aur-build と、新方式の .cache/aur-build を空なら削除。
  if [[ "${CONFIG[dry_run]}" != "yes" ]]; then
    for _h in /mnt/home/*; do
      [[ -d "$_h" ]] || continue
      rm -rf "${_h}/aur-build" "${_h}/.cache/aur-build" 2>/dev/null || true
    done

    # 一時 NOPASSWD sudoers の取り残しを最終掃除（trap の二重保険）。
    # ここを通れば、どの経路で来ても NOPASSWD 設定は残らない。
    if compgen -G "/mnt/etc/sudoers.d/*-aur-nopasswd" > /dev/null; then
      rm -f /mnt/etc/sudoers.d/*-aur-nopasswd 2>/dev/null || true
      print_warn "一時的な sudo NOPASSWD 設定の残骸を削除しました"
    fi
  fi

  # 初回ログインガイド生成（アンマウント前に実施）
  write_first_login_guide

  # systemd-resolved の resolv.conf シンボリックリンク設定を最終段階でホスト側から実施
  if [[ "${CONFIG[use_resolved]}" == "yes" ]]; then
    run_cmd "resolv.conf シンボリックリンク設定" \
      ln -sf /run/systemd/resolve/stub-resolv.conf /mnt/etc/resolv.conf
  fi

  # swapoff は swap がない場合でも失敗しないよう直接実行
  echo -ne "  ${CYAN}…${RESET} swap 無効化..."
  swapoff -a 2>/dev/null && echo -e "\r  ${GREEN}✔${RESET} swap 無効化   " || \
    echo -e "\r  ${GREEN}✔${RESET} swap なし（スキップ）"
  # インストールログを新システムに保存
  # （/tmp のログは再起動で消えるため、初回起動後のトラブルシュート用に残す）
  if [[ "${CONFIG[dry_run]}" != "yes" && -f "${CONFIG[log_file]}" && -d /mnt/var/log ]]; then
    cp "${CONFIG[log_file]}" /mnt/var/log/ 2>/dev/null \
      && print_ok "インストールログを保存: /var/log/$(basename "${CONFIG[log_file]}")" \
      || print_warn "ログのコピーに失敗しました（インストールには影響ありません）"
  fi

  # 【重要】umount より先に sync を独立したステップとして走らせること。
  #
  # umount -R は残っているダーティページを書き戻してから外すため、
  # 書き込みを一手に引き受けると低速なストレージ（USB/SD、回転HDD）では
  # 数分かかる。しかも表示が「アンマウント...」のままなので、利用者からは
  # 固まったようにしか見えない（実機でそう報告された）。
  # 先に sync を見せておけば、待ち時間の正体が「ディスクへの書き込み」だと
  # 分かるうえ、残量表示で終わりが見える。umount 自体はほぼ一瞬で終わる。
  if [[ "${CONFIG[dry_run]}" != "yes" ]]; then
    EXEC_TIMED_SHOW_DIRTY="yes"
    echo -ne "  ${CYAN}…${RESET} ディスクへの書き込みを完了中（未書き込み $(_dirty_mib) MiB）..."
    if _exec_timed "ディスクへの書き込みを完了中" sync; then
      echo -e "\r  ${GREEN}✔${RESET} ディスクへの書き込みを完了                              "
    else
      echo -e "\r  ${YELLOW}⚠${RESET} sync に失敗（アンマウント側で書き戻します）                              "
    fi
  fi

  # インストール自体は完了しているため、アンマウント失敗で exit しない
  echo -ne "  ${CYAN}…${RESET} アンマウント..."
  if [[ "${CONFIG[dry_run]}" == "yes" ]]; then
    echo -e "\r  ${YELLOW}⚠${RESET} アンマウント (ドライラン - スキップ)"
  elif _exec_timed "アンマウント" umount -R /mnt; then
    echo -e "\r  ${GREEN}✔${RESET} アンマウント                              "
  else
    echo -e "\r  ${YELLOW}⚠${RESET} アンマウントに失敗（インストール自体は完了しています）                              "
    print_warn "再起動前に手動で実行してください: umount -R /mnt"
  fi
  EXEC_TIMED_SHOW_DIRTY="no"
}

# ============================================
# インストール実行
# ============================================

run_install() {
  clear
  echo ""
  echo -e "  ${YELLOW}${BOLD}(o)${RESET} ${CYAN}${BOLD}${OS_NAME}${RESET}  ${GRAY}│${RESET}  ${BOLD}インストール実行中${RESET}"
  echo -e "  ${CYAN}$(printf '━%.0s' {1..48})${RESET}"
  echo ""

  # --- 進捗カウンター用の総ステップ数を算出（print_step が [n/N] を表示）---
  # 常に実行される11フェーズ（do_desktop と do_display_manager を含む。
  # COSMIC + SDDM 固定になったので、この2つは条件付きではなくなった）
  # + 条件付き1フェーズ（do_aur_helper）
  STEP_NUM=0
  STEP_TOTAL=11
  # 【重要】ここの条件は do_aur_helper の早期 return 条件と必ず一致させること。
  # 食い違うと do_aur_helper だけが計上されず、進捗表示が [12/11] のように
  # 総数を超える（wlogout を AUR からビルドしていた頃に実際に起きた）。
  { [[ "${CONFIG[aur_helper]}" != "none" ]] || [[ "${CONFIG[install_chrome]:-no}" == "yes" ]] \
      || [[ "${CONFIG[install_ytfzf]:-no}" == "yes" ]]; } \
    && STEP_TOTAL=$(( STEP_TOTAL + 1 ))

  # ファイルシステム固有ツールの確認（選択確定後にインストール）
  case "${CONFIG[fs_type]:-ext4}" in
    btrfs)
      if ! command -v mkfs.btrfs &>/dev/null; then
        print_warn "btrfs-progs をインストールします..."
        pacman -S --noconfirm btrfs-progs || { print_err "btrfs-progs のインストールに失敗しました。"; exit 1; }
      fi ;;
    xfs)
      if ! command -v mkfs.xfs &>/dev/null; then
        print_warn "xfsprogs をインストールします..."
        pacman -S --noconfirm xfsprogs || { print_err "xfsprogs のインストールに失敗しました。"; exit 1; }
      fi ;;
  esac

  if [[ "${CONFIG[dry_run]}" != "yes" ]]; then
    echo "" > "${CONFIG[log_file]}"
    print_ok "ログファイル: ${CONFIG[log_file]}"
  else
    print_warn "ドライランモードで動作中（変更は適用されません）"
    print_warn "生成される設定ファイルの確認先: ${SKEL_ROOT}"
  fi

  # 所要時間計測の開始
  INSTALL_START=$SECONDS
  STEP_LOG=()
  CURRENT_STEP_NAME=""
  CURRENT_STEP_TS=0

  # 【重要】ミラー選定はディスクを消す前に済ませること。
  # do_mirrorlist は Live 環境の /etc/pacman.d/mirrorlist だけを書き換え、
  # ディスクには触れない。一方ネットワーク次第で失敗しうる処理なので、
  # 消去の後に置くと「ディスクは空になったのにインストールできない」状態で止まる。
  do_mirrorlist
  do_partition
  do_format_and_mount
  do_pacstrap
  do_fstab
  do_chroot_config
  do_users
  do_aur_helper
  do_bootloader
  do_desktop
  do_display_manager
  do_cleanup

  # 最終ステップの所要時間を記録
  if [[ -n "${CURRENT_STEP_NAME:-}" ]]; then
    STEP_LOG+=("${CURRENT_STEP_NAME}|$(( SECONDS - CURRENT_STEP_TS ))")
    CURRENT_STEP_NAME=""
  fi
  STEP_TOTAL=0

  echo ""
  echo -e "  ${GREEN}${BOLD}✔ インストール完了！${RESET}  ${GRAY}再起動して日本語環境をお楽しみください${RESET}"
  echo -e "  ${GREEN}$(printf '━%.0s' {1..48})${RESET}"
  echo ""
  # ステップ別所要時間サマリー
  if [[ "${#STEP_LOG[@]}" -gt 0 ]]; then
    echo -e "  ${BOLD}ステップ別所要時間:${RESET}"
    for _entry in "${STEP_LOG[@]}"; do
      _sname="${_entry%|*}"
      _ssec="${_entry##*|}"
      echo -e "    ${GRAY}•${RESET} ${_sname}: $(( _ssec / 60 ))分$(( _ssec % 60 ))秒"
    done
    echo -e "  ${BOLD}総所要時間: $(( (SECONDS - INSTALL_START) / 60 ))分$(( (SECONDS - INSTALL_START) % 60 ))秒${RESET}"
    echo ""
  fi
  echo -e "  再起動コマンド: ${BOLD}reboot${RESET}"

  # 日本語入力のヒント（IME を導入した場合）
  if [[ "${CONFIG[jp_ime]:-none}" != "none" ]]; then
    echo ""
    echo -e "${CYAN}${BOLD}  ── 日本語入力について ──${RESET}"
    echo -e "  日本語入力のオン/オフは ${BOLD}Ctrl + Space${RESET} で切り替えます。"
    echo -e "  デスクトップに初回ログイン後、切り替わらない場合は"
    echo -e "  一度ログアウトして再ログインしてください。"
  fi

  # 外付けディスクへのインストール時は起動方法を案内
  if [[ "${CONFIG[disk_is_external]:-no}" == "yes" ]]; then
    echo ""
    echo -e "${YELLOW}${BOLD}  ── 外付けディスクからの起動について ──${RESET}"
    echo -e "  外付け SSD/HDD からブートするには、UEFI/BIOS で"
    echo -e "  起動順序（Boot Order）を変更する必要があります。\n"
    echo -e "  ${BOLD}一般的な手順:${RESET}"
    echo -e "    1. 再起動時に ${BOLD}F2 / F12 / Del / Esc${RESET} を連打"
    echo -e "       （メーカーにより異なります）"
    echo -e "    2. UEFI/BIOS メニューで ${BOLD}Boot${RESET} タブを開く"
    echo -e "    3. 外付けデバイス（USB や External NVMe）を最上位に移動"
    echo -e "    4. 設定を保存して再起動\n"
    echo -e "  ${BOLD}UEFI から一時的に起動デバイスを選ぶ場合:${RESET}"
    echo -e "    再起動時に ${BOLD}F12${RESET}（または F8/F10）を押して"
    echo -e "    Boot Menu を開き、外付けデバイスを選択してください。\n"
    echo -e "  ${BOLD}インストール済み Arch の UEFI エントリを確認:${RESET}"
    echo -e "    ${BOLD}efibootmgr -v${RESET}"
  fi
}


# ============================================
# メイン
# ============================================

main() {
  # 一時 NOPASSWD sudoers の取り残し防止（Ctrl+C / 途中失敗でも必ず消す）
  trap _cleanup_temp_sudoers EXIT
  trap _on_interrupt INT TERM
  trap _on_error ERR

  # root チェック
  if [[ "$EUID" -ne 0 ]]; then
    echo -e "${RED}エラー: このスクリプトは root で実行してください。${RESET}"
    echo "  例: sudo bash $(basename "$0")"
    exit 1
  fi

  # 必要コマンドの確認・自動インストール
  local missing_pkgs=()
  local deps=(
    "sgdisk:gptfdisk"
    "mkfs.fat:dosfstools"
    "mkfs.ext4:e2fsprogs"
    "mkswap:util-linux"
    "swapon:util-linux"
    "mount:util-linux"
    "umount:util-linux"
    "blkid:util-linux"
    "lsblk:util-linux"
    "findmnt:util-linux"
    "reflector:reflector"
    "arch-chroot:arch-install-scripts"
    "genfstab:arch-install-scripts"
    "pacstrap:arch-install-scripts"
    "partprobe:parted"
  )
  for dep in "${deps[@]}"; do
    local cmd="${dep%%:*}"
    local pkg="${dep##*:}"
    if ! command -v "$cmd" &>/dev/null; then
      # 同じパッケージが重複して入らないよう確認
      local already=0
      for p in "${missing_pkgs[@]:-}"; do [[ "$p" == "$pkg" ]] && already=1; done
      [[ "$already" -eq 0 ]] && missing_pkgs+=("$pkg")
    fi
  done

  if [[ "${#missing_pkgs[@]}" -gt 0 ]]; then
    echo -e "${YELLOW}⚠ 以下のパッケージが不足しています: ${missing_pkgs[*]}${RESET}"
    echo -e "  自動インストールします..."
    pacman -Sy --noconfirm "${missing_pkgs[@]}" || {
      echo -e "${RED}✘ 必要パッケージのインストールに失敗しました。${RESET}"
      echo "  手動で実行してください: pacman -S ${missing_pkgs[*]}"
      exit 1
    }
    echo -e "${GREEN}✔ 必要パッケージをインストールしました。${RESET}"
  fi

  # ブートモードを早期検出（step_partition_scheme で参照するため）
  CONFIG[boot_mode]=$(detect_boot_mode)

  # CPU ベンダー検出（マイクロコード選択・ブートローダー設定で共用）
  CONFIG[cpu_vendor]=$(grep -m1 'vendor_id' /proc/cpuinfo | awk '{print $3}')

  # 仮想環境検出
  local virt=""
  if command -v systemd-detect-virt &>/dev/null; then
    virt=$(systemd-detect-virt 2>/dev/null || echo "none")
  else
    virt="none"
  fi
  CONFIG[virt_env]="$virt"
  if [[ "$virt" != "none" ]]; then
    print_ok "仮想環境を検出しました: $virt"
  fi

  # Live環境の pacman.conf チューニング
  if [[ "${CONFIG[dry_run]}" != "yes" ]]; then
    tune_pacman_conf /etc/pacman.conf
    # 書き込みを最後にまとめて払わずに済むよう、ライトバックを前倒しする
    tune_writeback
  fi

  # 起動時のみ大きいロゴを出す。以降のステップは print_header（1行版）
  print_logo
  echo -e "  Arch Linux をベースに、日本語環境まで含めて自動構築します。"
  echo -e "  各ステップで設定を入力してください。\n"

  if ! confirm "開始しますか？"; then
    echo "中断しました。"
    exit 0
  fi

  step_check_network

  step_disk
  step_partition_scheme
  step_system
  step_users
  step_bootloader
  step_desktop
  step_config_source
  step_network
  step_mirror
  step_fonts
  step_extra_packages

  show_summary

  # 設定の修正ループ
  while true; do
    echo ""
    local action
    action=$(select_from_list "次のアクションを選択してください:" \
      "このままインストールを実行する" \
      "ディスクを変更する" \
      "パーティション構成・ファイルシステムを変更する" \
      "システム設定を変更する（ホスト名・タイムゾーン・GPUなど）" \
      "ユーザー設定を変更する" \
      "ブートローダーを変更する" \
      "設定の引き継ぎを変更する（ホストPC / GitHub / なし）" \
      "ネットワーク設定を変更する" \
      "追加パッケージを変更する" \
      "キャンセルして終了する")

    case "$action" in
      "このままインストールを実行する") break ;;
      "ディスクを変更する")                                   step_disk ;;
      "パーティション構成・ファイルシステムを変更する")       step_partition_scheme ;;
      "システム設定を変更する（ホスト名・タイムゾーン・GPUなど）") step_system ;;
      "ユーザー設定を変更する")                     step_users ;;
      "ブートローダーを変更する")                   step_bootloader ;;
      "設定の引き継ぎを変更する（ホストPC / GitHub / なし）") step_config_source ;;
      "ネットワーク設定を変更する")                 step_network ;;
      "追加パッケージを変更する")                   step_extra_packages ;;
      "キャンセルして終了する")
        echo -e "\n  インストールを中断しました。"
        exit 0
        ;;
    esac

    # 修正後にサマリーを再表示
    show_summary
  done

  # Windows 検出 + 自動パーティションの安全確認
  # （自動スキームは sgdisk --zap-all でディスク全体を消去するため、
  #   同一ディスク上の Windows も消える。ここで最終ガードを掛ける）
  #
  # 【重要】この確認は自己申告ではなく実際のディスクの状態で出る。
  # 以前は「Windows を残す」と答えた人にだけ出していたため、
  # 答えなかった人・答えを間違えた人は素通りできてしまっていた。
  if [[ "${CONFIG[windows_found]}" == "yes" && "${CONFIG[partition_scheme]}" != "manual" ]]; then
    echo ""
    print_warn "${CONFIG[disk]} に Windows（NTFS）がありますが、"
    print_warn "パーティション構成が「自動」のままです。"
    print_warn "このまま進むとディスク全体が消去され、Windows も消えます。"
    echo ""
    echo "      Windows を消してよい場合のみ、このまま進めます。"
    echo "      残したい場合は「いいえ」を選んで中断してください。"
    echo ""
    if ! confirm "${CONFIG[disk]} の Windows を消してよいですか？"; then
      print_err "中断しました。Windows を残すには、設定の修正メニューから"
      print_err "パーティション構成を「手動（fdisk）」に変更し、"
      print_err "Windows のパーティションには触れずに空き領域へ作成してください。"
      exit 1
    fi
  fi

  echo ""
  print_warn "この操作は取り消せません。ディスク ${CONFIG[disk]} の全データが完全に消去されます。"
  local final_confirm
  local tty_out tty_in; _resolve_tty tty_out tty_in
  echo -ne "  ${BOLD}${RED}実行する場合は大文字で YES と入力してください${RESET}: " > "$tty_out"
  _read_input final_confirm "$tty_in" "$tty_out"
  if [[ "$final_confirm" != "YES" ]]; then
    echo -e "\n  インストールをキャンセルしました。"
    exit 0
  fi
  run_install
}

main "$@"
