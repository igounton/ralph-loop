#!/bin/bash
# Cleanup module for ralph.sh
# Signal handlers and process cleanup
# Dependencies: constants.sh
#
# Properly cleans up all background processes and temporary files on exit.
# Runs on both normal exit (EXIT trap) and interrupt (called from handle_interrupt).
# Ensures no orphan processes remain after script exits.

# Cleanup function - kills background processes and removes temp files
cleanup() {
  # Kill spinner background process
  if [ -n "$SPINNER_PID" ] && kill -0 "$SPINNER_PID" 2>/dev/null; then
    kill "$SPINNER_PID" 2>/dev/null || true
    wait "$SPINNER_PID" 2>/dev/null || true
  fi
  SPINNER_PID=""

  # Kill Agent process tree if still running
  # The process tree is: script -> bash -> docker sandbox run
  # Killing just the script PID leaves the docker sandbox running
  if [ -n "$AGENT_PID" ] && kill -0 "$AGENT_PID" 2>/dev/null; then
    # Kill child processes first (bash -> docker), then the script process
    pkill -TERM -P "$AGENT_PID" 2>/dev/null || true
    kill "$AGENT_PID" 2>/dev/null || true
    wait "$AGENT_PID" 2>/dev/null || true
  fi
  AGENT_PID=""

  # Stop all running Docker sandboxes for this workspace
  # Finds sandboxes by matching the workspace path, regardless of agent prefix
  if command -v docker &>/dev/null && command -v jq &>/dev/null; then
    local sandboxes
    sandboxes=$(docker sandbox ls --json 2>/dev/null \
      | jq -r --arg ws "$SCRIPT_DIR" '(.vms // .sandboxes // [])[] | select(.status == "running" and (.workspaces[] == $ws)) | .name' 2>/dev/null)

    if [ -n "$sandboxes" ]; then
      echo -e "  ${Y}📦 Stopping sandbox...${R}"
      # Stop all matching sandboxes (pass all names at once)
      docker sandbox stop $sandboxes 2>/dev/null &
      local stop_pid=$!
      # Timeout after 5 seconds to avoid hanging on exit
      ( sleep 5 && kill "$stop_pid" 2>/dev/null ) &>/dev/null &
      local timeout_pid=$!
      if wait "$stop_pid" 2>/dev/null; then
        echo -e "  ${GR}✅ Sandbox stopped${R}"
      fi
      kill "$timeout_pid" 2>/dev/null || true
    fi
  fi

  # Remove temporary files
  [[ -n "$STEP_FILE" ]] && rm -f "$STEP_FILE" 2>/dev/null || true
  [[ -n "$PREVIEW_LINE_FILE" ]] && rm -f "$PREVIEW_LINE_FILE" 2>/dev/null || true
  [[ -n "$OUTPUT_FILE" ]] && rm -f "$OUTPUT_FILE" 2>/dev/null || true
  [[ -n "$FULL_OUTPUT_FILE" ]] && rm -f "$FULL_OUTPUT_FILE" 2>/dev/null || true
}

# Double CTRL+C to exit
# Tracks last interrupt time, requires second press within 3 seconds to exit
LAST_INTERRUPT=0

handle_interrupt() {
  local current_time=$(date +%s)
  local time_diff=$((current_time - LAST_INTERRUPT))

  if [ $time_diff -lt 3 ]; then
    # Second CTRL+C within 3 seconds - exit
    echo ""
    echo -e "${Y}Exiting...${R}"
    cleanup
    exit 130
  else
    # First CTRL+C - show warning and update timestamp
    LAST_INTERRUPT=$current_time
    echo ""
    echo -e "${Y}⚠️  Press CTRL+C again within 3 seconds to exit${R}"
  fi
}
