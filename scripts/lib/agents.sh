#!/bin/bash
# Agent module for ralph.sh
# Supported Docker Sandboxes agents and command construction

SUPPORTED_AGENTS="claude codex copilot cursor gemini opencode"

# Print the supported agent list for help and validation messages.
supported_agents_list() {
  echo "$SUPPORTED_AGENTS"
}

# Normalize user-provided agent names for case-insensitive matching.
normalize_agent_name() {
  echo "$1" | tr '[:upper:]' '[:lower:]'
}

# Return success when the agent slug is one Ralph knows how to run.
is_supported_agent() {
  case "$1" in
    claude|codex|copilot|cursor|gemini|opencode)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

# Human-friendly agent name for status and error messages.
agent_display_name() {
  case "$1" in
    claude) echo "Claude" ;;
    codex) echo "Codex" ;;
    copilot) echo "Copilot" ;;
    cursor) echo "Cursor" ;;
    gemini) echo "Gemini" ;;
    opencode) echo "OpenCode" ;;
    *) echo "$1" ;;
  esac
}

# Claude's stream-json output is currently the only fully parsed output path.
agent_uses_stream_json() {
  [ "$1" = "claude" ]
}

# Authentication command users can run before starting Ralph.
agent_login_command() {
  local agent="${1:-claude}"
  local sandbox_name="${2:-}"

  if [ -n "$sandbox_name" ]; then
    echo "sbx run --name $sandbox_name $agent ."
  else
    echo "sbx run $agent ."
  fi
}

# Convert project and agent values into Docker Sandboxes-safe name segments.
sanitize_sandbox_name_segment() {
  local value="${1:-sandbox}"

  value=$(printf "%s" "$value" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//; s/-+/-/g')

  if [ -z "$value" ]; then
    value="sandbox"
  fi

  printf "%s" "$value"
}

# Return an 8-character deterministic hash for an absolute project path.
sandbox_path_hash() {
  local project_path="$1"

  if command -v shasum >/dev/null 2>&1; then
    printf "%s" "$project_path" | shasum -a 256 | awk '{print substr($1, 1, 8)}'
  elif command -v sha256sum >/dev/null 2>&1; then
    printf "%s" "$project_path" | sha256sum | awk '{print substr($1, 1, 8)}'
  else
    printf "%s" "$project_path" | cksum | awk '{printf "%08x", $1}'
  fi
}

# Build Ralph's deterministic Docker Sandboxes name for this project and agent.
build_sandbox_name() {
  local agent="${1:-claude}"
  local project_path="${2:-$PWD}"
  local safe_agent
  local safe_project
  local hash

  safe_agent=$(sanitize_sandbox_name_segment "$agent")
  safe_project=$(sanitize_sandbox_name_segment "$(basename "$project_path")")
  hash=$(sandbox_path_hash "$project_path")

  printf "ralph-%s-%s-%s" "$safe_agent" "$safe_project" "$hash"
}

# Shell-quote any extra args passed after Ralph's own -- separator.
format_agent_extra_args() {
  local output=""
  local arg
  local quoted

  for arg in "${AGENT_EXTRA_ARGS[@]}"; do
    printf -v quoted "%q" "$arg"
    output="$output $quoted"
  done

  printf "%s" "$output"
}

# Build the command executed inside script(1)'s pseudo-TTY.
build_agent_command() {
  local agent="${1:-claude}"
  local sandbox_name="${2:-}"
  local extra_args
  local sbx_run
  extra_args=$(format_agent_extra_args)

  if [ -n "$sandbox_name" ]; then
    sbx_run="sbx run --name $sandbox_name $agent ."
  else
    sbx_run="sbx run $agent ."
  fi

  case "$agent" in
    claude)
      printf '%s -- --output-format stream-json --verbose%s -p "$PROMPT_CONTENT"' "$sbx_run" "$extra_args"
      ;;
    codex)
      printf '%s -- exec%s "$PROMPT_CONTENT"' "$sbx_run" "$extra_args"
      ;;
    copilot)
      printf '%s --%s -p "$PROMPT_CONTENT"' "$sbx_run" "$extra_args"
      ;;
    cursor)
      printf '%s -- -p%s "$PROMPT_CONTENT"' "$sbx_run" "$extra_args"
      ;;
    gemini)
      printf '%s --%s -p "$PROMPT_CONTENT"' "$sbx_run" "$extra_args"
      ;;
    opencode)
      printf '%s -- run%s "$PROMPT_CONTENT"' "$sbx_run" "$extra_args"
      ;;
    *)
      return 1
      ;;
  esac
}
