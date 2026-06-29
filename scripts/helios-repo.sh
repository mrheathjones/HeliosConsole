#!/bin/bash
#
# helios-repo.sh — one-shot manager for the Helios Console repository.
#
# Wraps the common git/gh operations and keeps the iCloud copy mirrored.
# The working git repo lives OUTSIDE iCloud Drive; `sync` pushes a .git-free
# copy into the iCloud folder so the original location stays current without
# ever putting a git database on iCloud (which corrupts over time).
#
# Usage:  ./scripts/helios-repo.sh <command> [args]
# Run     ./scripts/helios-repo.sh help   for the full command list.

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration (override via environment if your paths differ)
# ---------------------------------------------------------------------------
REPO="${HELIOS_REPO:-mrheathjones/HeliosConsole}"
WORK_DIR="${HELIOS_WORK_DIR:-${HOME}/Developer/HeliosConsole}"
ICLOUD_BASE="${HELIOS_ICLOUD_BASE:-${HOME}/Library/Mobile Documents/com~apple~CloudDocs/_APPS_IM_BUILDING/Vibe/HELIOS}"
ICLOUD_MIRROR="${ICLOUD_BASE}/HeliosConsole"
DEFAULT_BRANCH="${HELIOS_DEFAULT_BRANCH:-main}"

# ---------------------------------------------------------------------------
# Output helpers
# ---------------------------------------------------------------------------
if [[ -t 1 ]]; then
	C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'
	C_BLUE=$'\033[34m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_RED=$'\033[31m'
else
	C_RESET=""; C_BOLD=""; C_BLUE=""; C_GREEN=""; C_YELLOW=""; C_RED=""
fi

info()  { printf '%s==>%s %s\n'  "${C_BLUE}"   "${C_RESET}" "$*"; }
ok()    { printf '%s✓%s %s\n'    "${C_GREEN}"  "${C_RESET}" "$*"; }
warn()  { printf '%s!%s %s\n'    "${C_YELLOW}" "${C_RESET}" "$*" >&2; }
die()   { printf '%serror:%s %s\n' "${C_RED}"  "${C_RESET}" "$*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Guards
# ---------------------------------------------------------------------------
require_cmd() {
	command -v "$1" >/dev/null 2>&1 || die "required command '$1' not found in PATH"
}

require_repo() {
	[[ -d "${WORK_DIR}/.git" ]] || die "no git repo at ${WORK_DIR} (run: $(basename "$0") clone)"
}

current_branch() {
	git -C "${WORK_DIR}" rev-parse --abbrev-ref HEAD
}

# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------
cmd_clone() {
	require_cmd gh
	if [[ -d "${WORK_DIR}/.git" ]]; then
		warn "repo already exists at ${WORK_DIR}"
		return 0
	fi
	info "Cloning ${REPO} into ${WORK_DIR}"
	mkdir -p "$(dirname "${WORK_DIR}")"
	gh repo clone "${REPO}" "${WORK_DIR}"
	ok "Cloned."
}

cmd_status() {
	require_repo
	local branch
	branch="$(current_branch)"
	info "Repo:   ${REPO}"
	info "Path:   ${WORK_DIR}"
	info "Branch: ${C_BOLD}${branch}${C_RESET}"
	git -C "${WORK_DIR}" fetch --quiet origin "${branch}" 2>/dev/null || true
	local counts
	if counts="$(git -C "${WORK_DIR}" rev-list --left-right --count "origin/${branch}...HEAD" 2>/dev/null)"; then
		local behind ahead
		behind="$(echo "${counts}" | awk '{print $1}')"
		ahead="$(echo "${counts}" | awk '{print $2}')"
		info "Ahead ${ahead} / behind ${behind} vs origin/${branch}"
	fi
	echo
	git -C "${WORK_DIR}" status --short --branch
}

cmd_update() {
	require_repo
	local branch
	branch="$(current_branch)"
	info "Pulling (fast-forward only) on ${branch}"
	git -C "${WORK_DIR}" pull --ff-only origin "${branch}"
	ok "Up to date."
	cmd_sync
}

cmd_branch() {
	require_repo
	local name="${1:-}"
	[[ -n "${name}" ]] || die "usage: $(basename "$0") branch <name>"
	if git -C "${WORK_DIR}" show-ref --verify --quiet "refs/heads/${name}"; then
		info "Switching to existing branch ${name}"
		git -C "${WORK_DIR}" switch "${name}"
	else
		info "Creating branch ${name}"
		git -C "${WORK_DIR}" switch -c "${name}"
	fi
	ok "On branch $(current_branch)."
}

cmd_commit() {
	require_repo
	local msg="${1:-}"
	[[ -n "${msg}" ]] || die "usage: $(basename "$0") commit \"<message>\""
	if git -C "${WORK_DIR}" diff --quiet && git -C "${WORK_DIR}" diff --cached --quiet; then
		warn "nothing to commit — working tree clean"
		return 0
	fi
	git -C "${WORK_DIR}" add -A
	git -C "${WORK_DIR}" commit -m "${msg}"
	ok "Committed."
}

cmd_push() {
	require_repo
	local branch
	branch="$(current_branch)"
	info "Pushing ${branch} to origin"
	if git -C "${WORK_DIR}" rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1; then
		git -C "${WORK_DIR}" push
	else
		git -C "${WORK_DIR}" push -u origin "${branch}"
	fi
	ok "Pushed."
}

cmd_pr() {
	require_cmd gh
	require_repo
	local title="${1:-}"
	cmd_push
	local branch
	branch="$(current_branch)"
	info "Opening pull request"
	# Run gh from inside the repo and pin --head so branch detection never
	# depends on the caller's working directory.
	if [[ -n "${title}" ]]; then
		( cd "${WORK_DIR}" && gh pr create --base "${DEFAULT_BRANCH}" --head "${branch}" --title "${title}" --fill )
	else
		( cd "${WORK_DIR}" && gh pr create --base "${DEFAULT_BRANCH}" --head "${branch}" --fill )
	fi
}

cmd_sync() {
	require_cmd rsync
	[[ -d "${WORK_DIR}" ]] || die "working dir ${WORK_DIR} not found"
	info "Mirroring working tree → ${ICLOUD_MIRROR}"
	mkdir -p "${ICLOUD_MIRROR}"
	rsync -a --delete \
		--exclude '.git/' \
		--exclude 'DerivedData/' \
		--exclude 'build/' \
		--exclude '.build/' \
		--exclude 'xcuserdata/' \
		--exclude '*.xcuserstate' \
		--exclude '.DS_Store' \
		"${WORK_DIR}/" "${ICLOUD_MIRROR}/"
	ok "iCloud mirror updated (no .git)."
}

cmd_help() {
	cat <<EOF
${C_BOLD}helios-repo.sh${C_RESET} — manage the Helios Console repository

${C_BOLD}USAGE${C_RESET}
  $(basename "$0") <command> [args]

${C_BOLD}COMMANDS${C_RESET}
  clone               Clone ${REPO} into ${WORK_DIR}
  status              Show branch, ahead/behind, and working-tree status
  update | pull       Fast-forward pull from origin, then sync the iCloud mirror
  branch <name>       Create (or switch to) a feature branch
  commit "<msg>"      Stage all changes and commit
  push                Push the current branch (sets upstream on first push)
  pr [title]          Push, then open a pull request against ${DEFAULT_BRANCH}
  sync                Mirror the working tree into the iCloud folder (excludes .git)
  help                Show this help

${C_BOLD}PATHS${C_RESET}
  Working repo : ${WORK_DIR}
  iCloud mirror: ${ICLOUD_MIRROR}

Override paths with HELIOS_WORK_DIR, HELIOS_ICLOUD_BASE, HELIOS_REPO.
EOF
}

# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------
main() {
	require_cmd git
	local cmd="${1:-help}"
	shift || true
	case "${cmd}" in
		clone)            cmd_clone "$@" ;;
		status|st)        cmd_status "$@" ;;
		update|pull)      cmd_update "$@" ;;
		branch|br)        cmd_branch "$@" ;;
		commit|ci)        cmd_commit "$@" ;;
		push)             cmd_push "$@" ;;
		pr)               cmd_pr "$@" ;;
		sync)             cmd_sync "$@" ;;
		help|-h|--help)   cmd_help ;;
		*)                die "unknown command '${cmd}' (run: $(basename "$0") help)" ;;
	esac
}

main "$@"
