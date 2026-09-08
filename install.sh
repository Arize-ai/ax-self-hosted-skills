#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILLS_SRC="$SCRIPT_DIR/skills"

# Defaults
GLOBAL=false
COPY_MODE=false
FORCE=false
YES=false
UNINSTALL=false
LIST=false
PROJECT_DIR=""
MANUAL_AGENTS=()
SELECTED_SKILLS=()

show_usage() {
  cat <<'USAGE'
Arize Self-Hosted Skills Installer

Installs agent skills from this repo into Cursor / Claude / Codex / Copilot
skill directories. Does not install Arize AX or the ax CLI.

Usage: ./install.sh --project <dir> [flags]
       ./install.sh --global [flags]
       ./install.sh --list

One of --project or --global is required (except with --list).

Flags:
  --project <dir>   Install into a specific project directory (required unless --global)
  --global          Install to ~/.<agent>/skills/ instead of project-level
  --copy            Copy files instead of symlinking
  --force           Overwrite existing skills with same names
  --agent <name>    Manually specify agent (cursor, claude, codex, copilot) — repeatable
  --skill <name>    Only install/uninstall specific skills — repeatable
  --yes             Skip confirmation prompts
  --uninstall       Remove previously installed skill symlinks
  --list            List all available skills and exit
  --help            Show this help

Examples:
  ./install.sh --list
  ./install.sh --project ~/my-app
  ./install.sh --project ~/my-app --skill arize-alerts-troubleshoot
  ./install.sh --project . --agent cursor --yes
  ./install.sh --global
  ./install.sh --project ~/my-app --copy
  ./install.sh --project ~/my-app --uninstall
USAGE
}

usage() {
  show_usage
  exit 0
}

die_usage() {
  show_usage
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --global)     GLOBAL=true; shift ;;
    --project)    PROJECT_DIR="$2"; shift 2 ;;
    --copy)       COPY_MODE=true; shift ;;
    --force)      FORCE=true; shift ;;
    --skip-cli)   echo "Note: --skip-cli is ignored (this repo does not install the ax CLI)"; shift ;;
    --agent)      MANUAL_AGENTS+=("$2"); shift 2 ;;
    --skill)      SELECTED_SKILLS+=("$2"); shift 2 ;;
    --yes)        YES=true; shift ;;
    --uninstall)  UNINSTALL=true; shift ;;
    --list)       LIST=true; shift ;;
    --help|-h)    usage ;;
    *)            echo "Unknown flag: $1" >&2; die_usage ;;
  esac
done

# --- List mode ---

if [[ "$LIST" == true ]]; then
  echo "Available skills:"
  for skill in "$SKILLS_SRC"/*/; do
    [[ -d "$skill" ]] || continue
    echo "  $(basename "$skill")"
  done
  exit 0
fi

# --- Validate --skill names ---

if [[ ${#SELECTED_SKILLS[@]} -gt 0 ]]; then
  for name in "${SELECTED_SKILLS[@]}"; do
    if [[ ! -d "$SKILLS_SRC/$name" ]]; then
      echo "Error: unknown skill '$name'"
      echo ""
      echo "Available skills:"
      for skill in "$SKILLS_SRC"/*/; do
        [[ -d "$skill" ]] || continue
        echo "  $(basename "$skill")"
      done
      exit 1
    fi
  done
fi

# --- Agent detection ---

AGENTS=()

agent_skills_dir() {
  local agent="$1" base="$2"
  case "$agent" in
    cursor)  echo "$base/.cursor/skills" ;;
    claude)  echo "$base/.claude/skills" ;;
    codex)   echo "$base/.codex/skills" ;;
    copilot) echo "$base/.agents/skills" ;;
    *)       echo "$base/.$agent/skills" ;;
  esac
}

add_agent() {
  local name="$1"
  # Deduplicate: only add if not already in AGENTS
  for existing in "${AGENTS[@]+"${AGENTS[@]}"}"; do
    [[ "$existing" == "$name" ]] && return
  done
  AGENTS+=("$name")
}

detect_agents() {
  local base="$1"

  # Check for config directories in the target project/home
  if [[ -d "$base/.cursor" ]];        then add_agent "cursor"; fi
  if [[ -d "$base/.claude" ]];        then add_agent "claude"; fi
  if [[ -d "$base/.codex" ]];         then add_agent "codex"; fi
  if [[ -d "$base/.github/copilot" ]]; then add_agent "copilot"; fi

  # Also check for installed agent binaries (catches agents that haven't
  # created config dirs in this project yet)
  command -v cursor &>/dev/null && add_agent "cursor"
  command -v claude &>/dev/null && add_agent "claude"
  command -v codex  &>/dev/null && add_agent "codex"
  return 0
}

if [[ "$GLOBAL" != true && -z "$PROJECT_DIR" ]]; then
  echo "Error: --project <dir> is required (or use --global for global install)." >&2
  echo "" >&2
  die_usage
fi

if [[ ${#MANUAL_AGENTS[@]} -gt 0 ]]; then
  AGENTS=("${MANUAL_AGENTS[@]}")
elif [[ "$GLOBAL" == true ]]; then
  detect_agents "$HOME"
else
  detect_agents "$PROJECT_DIR"
fi

if [[ ${#AGENTS[@]} -eq 0 ]]; then
  if [[ -t 0 && "$YES" != true ]]; then
    echo "No agents detected (checked for .cursor/, .claude/, .codex/, .github/copilot/ directories and cursor/claude/codex binaries)."
    echo ""
    echo "Which agent(s) are you using?"
    echo "  1) cursor"
    echo "  2) claude"
    echo "  3) codex"
    echo "  4) copilot (GitHub Copilot)"
    echo ""
    read -rp "Enter number(s) separated by spaces [1]: " agent_choices
    agent_choices="${agent_choices:-1}"
    for choice in $agent_choices; do
      case "$choice" in
        1) AGENTS+=("cursor") ;;
        2) AGENTS+=("claude") ;;
        3) AGENTS+=("codex") ;;
        4) AGENTS+=("copilot") ;;
        *) echo "Unknown choice: $choice"; exit 1 ;;
      esac
    done
  else
    echo "No agents detected (checked for .cursor/, .claude/, .codex/, .github/copilot/ directories and cursor/claude/codex binaries)."
    echo "Use --agent <name> to specify manually, e.g.: ./install.sh --agent cursor"
    exit 1
  fi
fi

# --- Resolve base directory ---

if [[ "$GLOBAL" == true ]]; then
  BASE="$HOME"
else
  BASE="$PROJECT_DIR"
fi

echo "Arize Self-Hosted Skills Installer"
echo "=================================="
echo ""
echo "Detected agents: ${AGENTS[*]}"
if [[ "$GLOBAL" == true ]]; then
  echo "Scope: global ($HOME)"
else
  echo "Scope: project ($BASE)"
fi
echo ""

# --- Install or uninstall ---

install_skill() {
  local skill_src="$1" target="$2" skill_name
  skill_name="$(basename "$skill_src")"

  if [[ -e "$target" ]]; then
    if [[ "$FORCE" == true ]]; then
      rm -rf "$target"
    else
      echo "  Skipped $skill_name (already exists, use --force to overwrite)"
      return
    fi
  fi

  if [[ "$COPY_MODE" == true ]]; then
    cp -r "$skill_src" "$target"
    echo "  Copied  $skill_name -> $target"
  else
    ln -sfn "$skill_src" "$target"
    echo "  Linked  $skill_name -> $target"
  fi
}

uninstall_skill() {
  local skill_src="$1" target="$2" skill_name
  skill_name="$(basename "$skill_src")"

  if [[ -L "$target" && "$(readlink "$target")" == "$skill_src" ]]; then
    rm "$target"
    echo "  Removed $skill_name ($target)"
  elif [[ -L "$target" ]]; then
    echo "  Skipped $skill_name (symlink points elsewhere)"
  elif [[ -d "$target" ]]; then
    echo "  Skipped $skill_name (is a directory, not a symlink from this repo)"
  fi
}

# Build list of skills to process
SKILL_DIRS=()
if [[ ${#SELECTED_SKILLS[@]} -gt 0 ]]; then
  for name in "${SELECTED_SKILLS[@]}"; do
    SKILL_DIRS+=("$SKILLS_SRC/$name")
  done
else
  for skill in "$SKILLS_SRC"/*/; do
    [[ -d "$skill" ]] || continue
    SKILL_DIRS+=("$skill")
  done
fi

for agent in "${AGENTS[@]}"; do
  skills_dir="$(agent_skills_dir "$agent" "$BASE")"
  mkdir -p "$skills_dir"
  echo "Agent: $agent ($skills_dir)"

  for skill in "${SKILL_DIRS[@]}"; do
    [[ -d "$skill" ]] || continue
    target="$skills_dir/$(basename "$skill")"

    if [[ "$UNINSTALL" == true ]]; then
      uninstall_skill "$skill" "$target"
    else
      install_skill "$skill" "$target"
    fi
  done
done

echo ""

if [[ "$UNINSTALL" == true ]]; then
  echo "Done! Skills uninstalled."
  exit 0
fi

echo ""
if [[ "$COPY_MODE" == true ]]; then
  echo "Done! Skills copied into place."
else
  echo "Done! Skills are ready to use."
  echo "Keep this directory in place -- skills are symlinked here."
  echo "To make standalone copies instead, re-run with --copy."
fi
