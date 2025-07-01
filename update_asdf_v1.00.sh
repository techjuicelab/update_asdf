#!/bin/bash
# Author: TechJuiceLab & Gemini
# Description: asdf-vm update script with a fixed progress bar UI.

# ─── 1. 설정 (색상, 로그, 화면 레이아웃) ─────────────────────
# 색상 및 서식
reset=$'\e[0m'; green=$'\e[0;32m'; red=$'\e[0;31m'; yellow=$'\e[1;33m'
blue=$'\e[0;34m'; cyan=$'\e[0;36m'; magenta=$'\e[0;35m'; bold=$'\e[1m'

# 진행 바 문자
BAR_FILLED="█"
BAR_EMPTY=" "

# 로그 파일 생성
timestamp=$(date +%Y%m%d_%H%M%S)
log_dir="./logs"; mkdir -p "$log_dir"
log_file="$log_dir/asdf_update_$timestamp.log"

# 화면 레이아웃 상수
HEADER_LINES=4
MESSAGE_LINE=6
MAX_MESSAGES=15
PROGRESS_BAR_LINE=$((MESSAGE_LINE + MAX_MESSAGES + 2))
CURRENT_MESSAGE_LINE=$MESSAGE_LINE

# ─── 2. 화면 제어 및 UI 함수 ────────────────────────────────
# 스크립트 종료 시 커서 복원 및 정리
cleanup() {
  printf "\e[?25h" # 커서 보이기
  printf "\e[${PROGRESS_BAR_LINE};0H\n\n" # 커서를 진행 바 아래로 이동
}
trap cleanup EXIT

# 화면 초기화 및 커서 제어
hide_cursor() { printf "\e[?25l"; }
move_to_line() { printf "\e[$1;0H"; }
clear_line() { printf "\e[2K"; }
clear_screen_from() { printf "\e[$1J"; }

# 헤더 출력
print_header() {
  move_to_line 1
  echo -e "${bold}${blue}=======================================================${reset}"
  echo -e "${bold}${blue}  asdf-vm 플러그인 및 도구 자동 업데이트 (최종 버전)  ${reset}"
  echo -e "${bold}${blue}=======================================================${reset}"
  echo -e "${cyan}📄 로그 파일: ${log_file}${reset}"
}

# 메시지 추가 (화면과 로그에 동시 기록)
add_message() {
  local color=$1 message=$2
  echo "$(date '+%Y-%m-%d %H:%M:%S') - $message" >> "$log_file"
  
  if [ $CURRENT_MESSAGE_LINE -ge $((MESSAGE_LINE + MAX_MESSAGES)) ]; then
      CURRENT_MESSAGE_LINE=$MESSAGE_LINE
      move_to_line $MESSAGE_LINE
      clear_screen_from 0
  fi

  move_to_line $CURRENT_MESSAGE_LINE; clear_line
  echo -e "${color}${message}${reset}"
  CURRENT_MESSAGE_LINE=$((CURRENT_MESSAGE_LINE + 1))
}
echo_info() { add_message "$cyan" "ℹ️ $1"; }
echo_success() { add_message "$green" "✅ $1"; }
echo_warn() { add_message "$yellow" "⚠️ $1"; }
echo_error() { add_message "$red$bold" "🔥 $1"; }

# 명령어 실행 (출력은 로그 파일로, 성공/실패만 반환)
run_and_log() {
  local cmd="$1"
  echo -e "\nCOMMAND: $cmd" >> "$log_file"
  eval "$cmd" >> "$log_file" 2>&1
  return $?
}

# 진행 바 그리기
CURRENT_PCT=0
draw_progress_bar() {
  local pct=${1:-$CURRENT_PCT}
  CURRENT_PCT=$pct
  local len=40
  local fill=$((len * pct / 100)); local emp=$((len - fill))
  local bar_filled; for ((i=0; i<fill; i++)); do bar_filled+="$BAR_FILLED"; done
  local bar_empty; for ((i=0; i<emp; i++)); do bar_empty+="$BAR_EMPTY"; done
  
  move_to_line $PROGRESS_BAR_LINE; clear_line
  printf "${bold}📊 전체 진행률 ${reset}[${green}%s${reset}%s] ${green}%3d%%${reset}" \
    "$bar_filled" "$bar_empty" "$pct"
}

# ─── 3. 메인 로직 ──────────────────────────────────────
main() {
  clear; hide_cursor; print_header
  draw_progress_bar 0

  # asdf 수동 업데이트 확인
  echo_warn "이 스크립트는 '플러그인'과 '도구'만 업데이트합니다."
  echo_warn "asdf '자체'는 먼저 수동으로 업데이트해주세요. (예: brew upgrade asdf)"
  move_to_line $CURRENT_MESSAGE_LINE
  read -p "asdf 자체 업데이트를 완료하셨습니까? (y/n): " ready
  
  if [ "$(echo "$ready" | tr '[:upper:]' '[:lower:]')" != "y" ]; then
    echo_error "스크립트를 종료합니다. asdf를 먼저 업데이트해주세요."
    exit 0
  fi
  
  CURRENT_MESSAGE_LINE=$MESSAGE_LINE
  move_to_line $MESSAGE_LINE; clear_screen_from 0

  echo_info "asdf 플러그인 및 도구 업데이트를 시작합니다..."
  
  local plugins; plugins=($(asdf plugin list))
  local total_steps=$((1 + ${#plugins[@]}))
  local current_step=0

  # 1. 모든 플러그인 업데이트
  echo_info "[1/${total_steps} 단계] 모든 플러그인 업데이트 중..."
  if run_and_log "asdf plugin update --all"; then
    echo_success "모든 플러그인이 최신 버전입니다."
  else
    echo_error "일부 플러그인 업데이트에 실패했습니다. 로그를 확인하세요."
  fi
  current_step=$((current_step + 1))
  draw_progress_bar $((current_step * 100 / total_steps))
  sleep 1

  # 2. 각 도구 업데이트
  for plugin in "${plugins[@]}"; do
    local step_num=$((current_step + 1))
    echo_info "[${step_num}/${total_steps} 단계] '${plugin}' 확인 중..."
    
    local current_version; current_version=$(asdf current "$plugin" 2>/dev/null | awk '{print $2}')
    
    if [[ -z "$current_version" || "$current_version" == "system" || "$current_version" == "Version" ]]; then
      echo_warn "'$plugin'에 설정된 버전이 없거나 잘못되었습니다. 건너뜁니다."
    else
      local latest_version; latest_version=$(asdf latest "$plugin")
      if [ "$current_version" == "$latest_version" ]; then
        echo_success "'$plugin'은(는) 이미 최신 버전($current_version)입니다."
      else
        echo_info "'$plugin' 업데이트 필요: ${current_version} -> ${latest_version}"
        echo_info " ↳ 설치를 시작합니다... (자세한 내용은 로그 파일 참조)"
        if run_and_log "asdf install '$plugin' '$latest_version'"; then
          echo_info " ↳ Global 버전을 설정합니다..."
          # ✅ 최종 수정: 현재 스크립트의 위치에 영향을 주지 않도록 ( ) 서브셸 안에서 홈 디렉터리로 이동 후 `asdf set` 실행
          if run_and_log "(cd ~ && asdf set '$plugin' '$latest_version')"; then
            echo_success "'$plugin'이(가) ${latest_version} 버전으로 업데이트되었습니다."
          else
            echo_error "'$plugin' v${latest_version} Global 설정에 실패했습니다."
          fi
        else
          echo_error "'$plugin' v${latest_version} 설치에 실패했습니다."
        fi
      fi
    fi
    current_step=$((current_step + 1))
    draw_progress_bar $((current_step * 100 / total_steps))
    sleep 0.5
  done

  echo_success "🎊 모든 업데이트 작업이 완료되었습니다!"
}

# ─── 4. 스크립트 실행 ───────────────────────────────────
main
