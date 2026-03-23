#!/bin/bash
# Test script for ralph.sh step timing functionality
# Verifies that step timing tracking, recording, and formatting work correctly

set -e

# Get script directory for consistent paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source the required modules
source "$PROJECT_ROOT/scripts/lib/constants.sh"
source "$PROJECT_ROOT/scripts/lib/terminal.sh"
source "$PROJECT_ROOT/scripts/lib/timing.sh"
source "$PROJECT_ROOT/scripts/lib/output.sh"

# Test tracking
TESTS_PASSED=0
TESTS_FAILED=0
CURRENT_TEST=""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

# Test utilities
test_start() {
  CURRENT_TEST="$1"
  echo -n "Testing: $CURRENT_TEST... "
}

test_pass() {
  echo -e "${GREEN}PASS${NC}"
  TESTS_PASSED=$((TESTS_PASSED + 1))
}

test_fail() {
  local reason="${1:-}"
  echo -e "${RED}FAIL${NC}"
  if [ -n "$reason" ]; then
    echo -e "  ${YELLOW}Reason: $reason${NC}"
  fi
  TESTS_FAILED=$((TESTS_FAILED + 1))
}

# ═══════════════════════════════════════════════════════════════════════════════
# TEST: format_step_duration
# ═══════════════════════════════════════════════════════════════════════════════

test_format_step_duration_seconds() {
  test_start "format_step_duration seconds (<60s)"

  local result=$(format_step_duration 45)
  if [ "$result" = "45s" ]; then
    test_pass
  else
    test_fail "Expected '45s', got '$result'"
  fi
}

test_format_step_duration_minutes() {
  test_start "format_step_duration minutes (>=60s)"

  local result=$(format_step_duration 125)
  if [ "$result" = "02:05" ]; then
    test_pass
  else
    test_fail "Expected '02:05', got '$result'"
  fi
}

test_format_step_duration_zero() {
  test_start "format_step_duration zero"

  local result=$(format_step_duration 0)
  if [ "$result" = "0s" ]; then
    test_pass
  else
    test_fail "Expected '0s', got '$result'"
  fi
}

test_format_step_duration_exactly_60() {
  test_start "format_step_duration exactly 60s"

  local result=$(format_step_duration 60)
  if [ "$result" = "01:00" ]; then
    test_pass
  else
    test_fail "Expected '01:00', got '$result'"
  fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# TEST: format_duration (for total time)
# ═══════════════════════════════════════════════════════════════════════════════

test_format_duration_minutes() {
  test_start "format_duration minutes (no hours)"

  local result=$(format_duration 125)
  if [ "$result" = "02:05" ]; then
    test_pass
  else
    test_fail "Expected '02:05', got '$result'"
  fi
}

test_format_duration_hours() {
  test_start "format_duration with hours"

  local result=$(format_duration 3725)  # 1 hour, 2 mins, 5 secs
  if [ "$result" = "01:02:05" ]; then
    test_pass
  else
    test_fail "Expected '01:02:05', got '$result'"
  fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# TEST: get_step_index
# ═══════════════════════════════════════════════════════════════════════════════

test_get_step_index_valid() {
  test_start "get_step_index returns correct index"

  # Testing is at index 7 in STEP_NAMES array
  local result=$(get_step_index "Testing")
  if [ "$result" = "7" ]; then
    test_pass
  else
    test_fail "Expected '7', got '$result'"
  fi
}

test_get_step_index_invalid() {
  test_start "get_step_index returns -1 for unknown step"

  local result=$(get_step_index "Unknown Step")
  if [ "$result" = "-1" ]; then
    test_pass
  else
    test_fail "Expected '-1', got '$result'"
  fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# TEST: get_step_emoji
# ═══════════════════════════════════════════════════════════════════════════════

test_get_step_emoji_testing() {
  test_start "get_step_emoji for Testing"

  local result=$(get_step_emoji "Testing")
  if [ "$result" = "🧪" ]; then
    test_pass
  else
    test_fail "Expected '🧪', got '$result'"
  fi
}

test_get_step_emoji_unknown() {
  test_start "get_step_emoji returns empty for unknown step"

  local result=$(get_step_emoji "Unknown")
  if [ -z "$result" ]; then
    test_pass
  else
    test_fail "Expected empty string, got '$result'"
  fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# TEST: init_iteration_step_times
# ═══════════════════════════════════════════════════════════════════════════════

test_init_iteration_clears_times() {
  test_start "init_iteration_step_times clears previous times"

  # Set some values
  ITERATION_STEP_VALUES[4]=100
  ITERATION_STEP_VALUES[5]=50

  # Initialize
  init_iteration_step_times

  # Check all values are 0
  local all_zero=true
  for val in "${ITERATION_STEP_VALUES[@]}"; do
    if [ "$val" != "0" ]; then
      all_zero=false
      break
    fi
  done

  if [ "$all_zero" = true ]; then
    test_pass
  else
    test_fail "Expected all zeros, got non-zero values"
  fi
}

test_init_iteration_starts_thinking() {
  test_start "init_iteration_step_times starts with Thinking"

  init_iteration_step_times

  if [ "$CURRENT_STEP_NAME" = "Thinking" ]; then
    test_pass
  else
    test_fail "Expected 'Thinking', got '$CURRENT_STEP_NAME'"
  fi
}

test_init_iteration_sets_start_time() {
  test_start "init_iteration_step_times sets start time"

  local before=$(date +%s)
  init_iteration_step_times
  local after=$(date +%s)

  if [ "$CURRENT_STEP_START" -ge "$before" ] && [ "$CURRENT_STEP_START" -le "$after" ]; then
    test_pass
  else
    test_fail "Start time not set correctly"
  fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# TEST: record_step_time
# ═══════════════════════════════════════════════════════════════════════════════

test_record_step_time_new_step() {
  test_start "record_step_time starts new step"

  # Reset state
  ITERATION_STEP_VALUES=(0 0 0 0 0 0 0 0 0 0 0 0 0 0)
  SESSION_STEP_VALUES=(0 0 0 0 0 0 0 0 0 0 0 0 0 0)
  CURRENT_STEP_NAME=""
  CURRENT_STEP_START=0

  record_step_time "Testing"

  if [ "$CURRENT_STEP_NAME" = "Testing" ] && [ "$CURRENT_STEP_START" -gt 0 ]; then
    test_pass
  else
    test_fail "Expected 'Testing' with start time, got '$CURRENT_STEP_NAME' with $CURRENT_STEP_START"
  fi
}

test_record_step_time_clears_on_empty() {
  test_start "record_step_time clears on empty string"

  # Set up current step
  CURRENT_STEP_NAME="Testing"
  CURRENT_STEP_START=$(date +%s)

  record_step_time ""

  if [ -z "$CURRENT_STEP_NAME" ] && [ "$CURRENT_STEP_START" -eq 0 ]; then
    test_pass
  else
    test_fail "Expected cleared state, got '$CURRENT_STEP_NAME' with $CURRENT_STEP_START"
  fi
}

test_record_step_accumulates_iteration_times() {
  test_start "record_step_time accumulates iteration times"

  # Reset state
  ITERATION_STEP_VALUES=(0 0 0 0 0 0 0 0 0 0 0 0 0 0)
  SESSION_STEP_VALUES=(0 0 0 0 0 0 0 0 0 0 0 0 0 0)

  # Simulate step with known duration by manipulating start time
  CURRENT_STEP_NAME="Testing"
  CURRENT_STEP_START=$(($(date +%s) - 5))  # 5 seconds ago

  record_step_time "Linting"

  local idx=$(get_step_index "Testing")
  local recorded=${ITERATION_STEP_VALUES[$idx]}
  # Allow for slight timing variance (4-6 seconds)
  if [ "$recorded" -ge 4 ] && [ "$recorded" -le 6 ]; then
    test_pass
  else
    test_fail "Expected ~5s, got ${recorded}s"
  fi
}

test_record_step_accumulates_session_times() {
  test_start "record_step_time accumulates session times"

  # Reset state
  ITERATION_STEP_VALUES=(0 0 0 0 0 0 0 0 0 0 0 0 0 0)
  SESSION_STEP_VALUES=(0 0 0 0 0 0 0 0 0 0 0 0 0 0)

  # First step
  CURRENT_STEP_NAME="Testing"
  CURRENT_STEP_START=$(($(date +%s) - 3))  # 3 seconds ago
  record_step_time "Linting"

  # Simulate another iteration by adding to Testing again
  CURRENT_STEP_NAME="Testing"
  CURRENT_STEP_START=$(($(date +%s) - 2))  # 2 seconds ago
  record_step_time "Committing"

  local idx=$(get_step_index "Testing")
  local session_time=${SESSION_STEP_VALUES[$idx]}
  # Should be ~5s total (3 + 2)
  if [ "$session_time" -ge 4 ] && [ "$session_time" -le 6 ]; then
    test_pass
  else
    test_fail "Expected ~5s total, got ${session_time}s"
  fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# TEST: detect_step
# ═══════════════════════════════════════════════════════════════════════════════

test_detect_step_testing() {
  test_start "detect_step identifies Testing"

  local result=$(detect_step "Running npm test")
  # Result includes trailing spaces for display alignment
  if echo "$result" | grep -q "Testing"; then
    test_pass
  else
    test_fail "Expected 'Testing', got '$result'"
  fi
}

test_detect_step_linting() {
  test_start "detect_step identifies Linting"

  local result=$(detect_step "Running eslint on files")
  if echo "$result" | grep -q "Linting"; then
    test_pass
  else
    test_fail "Expected 'Linting', got '$result'"
  fi
}

test_detect_step_committing() {
  test_start "detect_step identifies Committing"

  local result=$(detect_step "git commit -m 'fix: bug'")
  if echo "$result" | grep -q "Committing"; then
    test_pass
  else
    test_fail "Expected 'Committing', got '$result'"
  fi
}

test_detect_step_unknown() {
  test_start "detect_step returns empty for unknown"

  local result=$(detect_step "Just some random text")
  if [ -z "$result" ]; then
    test_pass
  else
    test_fail "Expected empty, got '$result'"
  fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# TEST: All step emojis defined
# ═══════════════════════════════════════════════════════════════════════════════

test_all_step_emojis_defined() {
  test_start "All 14 step types have emojis defined"

  local missing=()
  for step in "${STEP_NAMES[@]}"; do
    local emoji=$(get_step_emoji "$step")
    if [ -z "$emoji" ]; then
      missing+=("$step")
    fi
  done

  if [ ${#missing[@]} -eq 0 ]; then
    test_pass
  else
    test_fail "Missing emojis for: ${missing[*]}"
  fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# TEST: detect_step returns exact STEP_NAMES (critical bug fix)
# ═══════════════════════════════════════════════════════════════════════════════

test_detect_step_returns_exact_names() {
  test_start "detect_step returns names matching STEP_NAMES exactly"

  # Test cases: input → expected step name
  local test_cases=(
    "npm run build:Implementing"
    "git commit -m test:Committing"
    "vitest running:Testing"
    "the error is here:Debugging"
    "eslint --fix:Linting"
    "npm run typecheck:Typechecking"
    "test.spec.ts file:Writing tests"
    "npm install lodash:Installing"
    "WebFetch docs:Web research"
    "verifying the change:Verifying"
    "AskUserQuestion:Waiting"
    "EnterPlanMode:Planning"
    "Read file_path=test:Reading code"
    "let me think about:Thinking"
  )

  local failed=()
  for tc in "${test_cases[@]}"; do
    local input="${tc%%:*}"
    local expected="${tc#*:}"
    local detected=$(detect_step "$input")

    # Verify exact match (no trailing whitespace)
    if [ "$detected" != "$expected" ]; then
      failed+=("'$input' → '$detected' (expected '$expected')")
    fi

    # Verify get_step_index finds it
    local idx=$(get_step_index "$detected")
    if [ "$idx" = "-1" ] && [ -n "$detected" ]; then
      failed+=("'$detected' not found in STEP_NAMES")
    fi
  done

  if [ ${#failed[@]} -eq 0 ]; then
    test_pass
  else
    test_fail "Mismatches: ${failed[*]}"
  fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# TEST: detect_step for all 14 steps
# ═══════════════════════════════════════════════════════════════════════════════

test_detect_step_thinking() {
  test_start "detect_step identifies Thinking"
  local result=$(detect_step "let me think about this")
  if [ "$result" = "Thinking" ]; then
    test_pass
  else
    test_fail "Expected 'Thinking', got '$result'"
  fi
}

test_detect_step_planning() {
  test_start "detect_step identifies Planning"
  local result=$(detect_step "EnterPlanMode")
  if [ "$result" = "Planning" ]; then
    test_pass
  else
    test_fail "Expected 'Planning', got '$result'"
  fi
}

test_detect_step_reading_code() {
  test_start "detect_step identifies Reading code"
  local result=$(detect_step "Read file_path=/src/main.ts")
  if [ "$result" = "Reading code" ]; then
    test_pass
  else
    test_fail "Expected 'Reading code', got '$result'"
  fi
}

test_detect_step_web_research() {
  test_start "detect_step identifies Web research"
  local result=$(detect_step "WebFetch documentation")
  if [ "$result" = "Web research" ]; then
    test_pass
  else
    test_fail "Expected 'Web research', got '$result'"
  fi
}

test_detect_step_implementing() {
  test_start "detect_step identifies Implementing"
  local result=$(detect_step "Edit file_path=/src/app.tsx")
  if [ "$result" = "Implementing" ]; then
    test_pass
  else
    test_fail "Expected 'Implementing', got '$result'"
  fi
}

test_detect_step_debugging() {
  test_start "detect_step identifies Debugging"
  local result=$(detect_step "the error is in line 42")
  if [ "$result" = "Debugging" ]; then
    test_pass
  else
    test_fail "Expected 'Debugging', got '$result'"
  fi
}

test_detect_step_writing_tests() {
  test_start "detect_step identifies Writing tests"
  local result=$(detect_step "creating test file")
  if [ "$result" = "Writing tests" ]; then
    test_pass
  else
    test_fail "Expected 'Writing tests', got '$result'"
  fi
}

test_detect_step_installing() {
  test_start "detect_step identifies Installing"
  local result=$(detect_step "npm install lodash")
  if [ "$result" = "Installing" ]; then
    test_pass
  else
    test_fail "Expected 'Installing', got '$result'"
  fi
}

test_detect_step_verifying() {
  test_start "detect_step identifies Verifying"
  local result=$(detect_step "verifying the changes")
  if [ "$result" = "Verifying" ]; then
    test_pass
  else
    test_fail "Expected 'Verifying', got '$result'"
  fi
}

test_detect_step_waiting() {
  test_start "detect_step identifies Waiting"
  local result=$(detect_step "AskUserQuestion")
  if [ "$result" = "Waiting" ]; then
    test_pass
  else
    test_fail "Expected 'Waiting', got '$result'"
  fi
}

test_detect_step_typechecking() {
  test_start "detect_step identifies Typechecking"
  local result=$(detect_step "npm run typecheck")
  if [ "$result" = "Typechecking" ]; then
    test_pass
  else
    test_fail "Expected 'Typechecking', got '$result'"
  fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# TEST: detect_step with Bash tool events (from parse_json_content)
# ═══════════════════════════════════════════════════════════════════════════════

test_detect_step_bash_testing() {
  test_start "detect_step identifies Testing from Bash tool event"
  local result=$(detect_step "Bash command=npm test")
  if [ "$result" = "Testing" ]; then
    test_pass
  else
    test_fail "Expected 'Testing', got '$result'"
  fi
}

test_detect_step_bash_linting() {
  test_start "detect_step identifies Linting from Bash tool event"
  local result=$(detect_step "Bash command=eslint src/")
  if [ "$result" = "Linting" ]; then
    test_pass
  else
    test_fail "Expected 'Linting', got '$result'"
  fi
}

test_detect_step_bash_building() {
  test_start "detect_step identifies Implementing from Bash build command"
  local result=$(detect_step "Bash command=npm run build")
  if [ "$result" = "Implementing" ]; then
    test_pass
  else
    test_fail "Expected 'Implementing', got '$result'"
  fi
}

test_detect_step_bash_typecheck() {
  test_start "detect_step identifies Typechecking from Bash tool event"
  local result=$(detect_step "Bash command=tsc --noEmit")
  if [ "$result" = "Typechecking" ]; then
    test_pass
  else
    test_fail "Expected 'Typechecking', got '$result'"
  fi
}

test_detect_step_bash_install() {
  test_start "detect_step identifies Installing from Bash tool event"
  local result=$(detect_step "Bash command=npm install lodash")
  if [ "$result" = "Installing" ]; then
    test_pass
  else
    test_fail "Expected 'Installing', got '$result'"
  fi
}

test_detect_step_bash_playwright() {
  test_start "detect_step identifies Testing from Bash playwright event"
  local result=$(detect_step "Bash command=npx playwright test")
  if [ "$result" = "Testing" ]; then
    test_pass
  else
    test_fail "Expected 'Testing', got '$result'"
  fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# TEST: parse_json_content
# ═══════════════════════════════════════════════════════════════════════════════

test_parse_json_text_field() {
  test_start "parse_json_content extracts text field"
  local result=$(parse_json_content '{"type":"content_block_delta","delta":{"text":"hello world"}}')
  if echo "$result" | grep -q "hello world"; then
    test_pass
  else
    test_fail "Expected 'hello world', got '$result'"
  fi
}

test_parse_json_tool_use_read() {
  test_start "parse_json_content extracts Read tool_use event"
  local result=$(parse_json_content '{"type":"content_block_start","content_block":{"type":"tool_use","name":"Read","input":{"file_path":"/src/main.ts"}}}')
  if [ "$result" = "Read file_path=/src/main.ts" ]; then
    test_pass
  else
    test_fail "Expected 'Read file_path=/src/main.ts', got '$result'"
  fi
}

test_parse_json_tool_use_bash() {
  test_start "parse_json_content extracts Bash tool_use with command"
  local result=$(parse_json_content '{"type":"content_block_start","content_block":{"type":"tool_use","name":"Bash","input":{"command":"npm test"}}}')
  if [ "$result" = "Bash command=npm test" ]; then
    test_pass
  else
    test_fail "Expected 'Bash command=npm test', got '$result'"
  fi
}

test_parse_json_tool_use_grep() {
  test_start "parse_json_content extracts Grep tool_use with pattern"
  local result=$(parse_json_content '{"type":"content_block_start","content_block":{"type":"tool_use","name":"Grep","input":{"pattern":"TODO"}}}')
  if [ "$result" = "Grep pattern=TODO" ]; then
    test_pass
  else
    test_fail "Expected 'Grep pattern=TODO', got '$result'"
  fi
}

test_parse_json_tool_use_webfetch() {
  test_start "parse_json_content extracts WebFetch tool_use (no extra fields)"
  local result=$(parse_json_content '{"type":"content_block_start","content_block":{"type":"tool_use","name":"WebFetch","input":{"url":"https://example.com"}}}')
  if [ "$result" = "WebFetch" ]; then
    test_pass
  else
    test_fail "Expected 'WebFetch', got '$result'"
  fi
}

test_parse_json_non_json() {
  test_start "parse_json_content returns non-JSON as-is"
  local result=$(parse_json_content "just plain text")
  if [ "$result" = "just plain text" ]; then
    test_pass
  else
    test_fail "Expected 'just plain text', got '$result'"
  fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# TEST: Full flow - detect → index → record
# ═══════════════════════════════════════════════════════════════════════════════

test_full_timing_flow() {
  test_start "Full flow: detect_step → get_step_index → record_step_time"

  # Reset state
  ITERATION_STEP_VALUES=(0 0 0 0 0 0 0 0 0 0 0 0 0 0)
  SESSION_STEP_VALUES=(0 0 0 0 0 0 0 0 0 0 0 0 0 0)
  CURRENT_STEP_NAME=""
  CURRENT_STEP_START=0

  # Simulate: start with Testing, then switch to Committing
  local detected1=$(detect_step "vitest running tests")
  CURRENT_STEP_NAME="$detected1"
  CURRENT_STEP_START=$(($(date +%s) - 3))  # 3 seconds ago

  local detected2=$(detect_step "git commit -m 'feat: test'")
  record_step_time "$detected2"

  # Verify Testing time was recorded
  local testing_idx=$(get_step_index "Testing")
  local testing_time=${ITERATION_STEP_VALUES[$testing_idx]}

  if [ "$testing_time" -ge 2 ] && [ "$testing_time" -le 4 ]; then
    test_pass
  else
    test_fail "Expected Testing ~3s, got ${testing_time}s (idx=$testing_idx)"
  fi
}

test_step_transition_records_correct_step() {
  test_start "Step transition records time to correct step"

  # Reset
  ITERATION_STEP_VALUES=(0 0 0 0 0 0 0 0 0 0 0 0 0 0)
  SESSION_STEP_VALUES=(0 0 0 0 0 0 0 0 0 0 0 0 0 0)

  # Start Implementing
  CURRENT_STEP_NAME="Implementing"
  CURRENT_STEP_START=$(($(date +%s) - 5))

  # Switch to Debugging
  record_step_time "Debugging"

  # Verify Implementing got the time (not Debugging)
  local impl_idx=$(get_step_index "Implementing")
  local debug_idx=$(get_step_index "Debugging")
  local impl_time=${ITERATION_STEP_VALUES[$impl_idx]}
  local debug_time=${ITERATION_STEP_VALUES[$debug_idx]}

  if [ "$impl_time" -ge 4 ] && [ "$impl_time" -le 6 ] && [ "$debug_time" -eq 0 ]; then
    test_pass
  else
    test_fail "Implementing=${impl_time}s (expected ~5s), Debugging=${debug_time}s (expected 0)"
  fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# Main test runner
# ═══════════════════════════════════════════════════════════════════════════════

main() {
  echo ""
  echo "═══════════════════════════════════════════════════════════════"
  echo " Ralph Step Timing Test Suite"
  echo "═══════════════════════════════════════════════════════════════"
  echo ""

  # format_step_duration tests
  echo "--- format_step_duration Tests ---"
  test_format_step_duration_seconds
  test_format_step_duration_minutes
  test_format_step_duration_zero
  test_format_step_duration_exactly_60
  echo ""

  # format_duration tests
  echo "--- format_duration Tests ---"
  test_format_duration_minutes
  test_format_duration_hours
  echo ""

  # get_step_index tests
  echo "--- get_step_index Tests ---"
  test_get_step_index_valid
  test_get_step_index_invalid
  echo ""

  # get_step_emoji tests
  echo "--- get_step_emoji Tests ---"
  test_get_step_emoji_testing
  test_get_step_emoji_unknown
  echo ""

  # init_iteration_step_times tests
  echo "--- init_iteration_step_times Tests ---"
  test_init_iteration_clears_times
  test_init_iteration_starts_thinking
  test_init_iteration_sets_start_time
  echo ""

  # record_step_time tests
  echo "--- record_step_time Tests ---"
  test_record_step_time_new_step
  test_record_step_time_clears_on_empty
  test_record_step_accumulates_iteration_times
  test_record_step_accumulates_session_times
  echo ""

  # detect_step tests
  echo "--- detect_step Tests ---"
  test_detect_step_testing
  test_detect_step_linting
  test_detect_step_committing
  test_detect_step_unknown
  echo ""

  # Step emojis tests
  echo "--- Step Emojis Tests ---"
  test_all_step_emojis_defined
  echo ""

  # Critical bug fix test
  echo "--- detect_step Exact Name Match Tests ---"
  test_detect_step_returns_exact_names
  echo ""

  # All 14 step detection tests
  echo "--- detect_step All Steps Tests ---"
  test_detect_step_thinking
  test_detect_step_planning
  test_detect_step_reading_code
  test_detect_step_web_research
  test_detect_step_implementing
  test_detect_step_debugging
  test_detect_step_writing_tests
  test_detect_step_installing
  test_detect_step_verifying
  test_detect_step_waiting
  test_detect_step_typechecking
  echo ""

  # Bash tool detection tests
  echo "--- Bash Tool Detection Tests ---"
  test_detect_step_bash_testing
  test_detect_step_bash_linting
  test_detect_step_bash_building
  test_detect_step_bash_typecheck
  test_detect_step_bash_install
  test_detect_step_bash_playwright
  echo ""

  # parse_json_content tests
  echo "--- parse_json_content Tests ---"
  test_parse_json_text_field
  test_parse_json_tool_use_read
  test_parse_json_tool_use_bash
  test_parse_json_tool_use_grep
  test_parse_json_tool_use_webfetch
  test_parse_json_non_json
  echo ""

  # Full flow tests
  echo "--- Full Timing Flow Tests ---"
  test_full_timing_flow
  test_step_transition_records_correct_step
  echo ""

  # Summary
  echo "═══════════════════════════════════════════════════════════════"
  local total=$((TESTS_PASSED + TESTS_FAILED))
  if [ $TESTS_FAILED -eq 0 ]; then
    echo -e "${GREEN}All $total tests passed!${NC}"
  else
    echo -e "${RED}$TESTS_FAILED of $total tests failed${NC}"
  fi
  echo "═══════════════════════════════════════════════════════════════"

  # Exit with failure if any tests failed
  if [ $TESTS_FAILED -gt 0 ]; then
    exit 1
  fi
}

main "$@"
