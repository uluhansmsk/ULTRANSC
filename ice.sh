#!/usr/bin/env bash
set -euo pipefail

# ============================
# CONFIG
# ============================
DEFAULT_BEFORE=5
DEFAULT_AFTER=5
SIM_THRESHOLD=80   # % similarity threshold to reject duplicates
BLOCK_DIR="blocks"
mkdir -p "$BLOCK_DIR"

# ============================
# USAGE CHECK
# ============================
if [[ $# -lt 3 ]]; then
    echo "Usage: $0 <lecture-pattern...> -- <keyword...>"
    exit 1
fi

# Split args at --
SEP_INDEX=0
for i in $(seq 1 $#); do
    if [[ "${!i}" == "--" ]]; then
        SEP_INDEX=$i
        break
    fi
done

if [[ $SEP_INDEX -eq 0 ]]; then
    echo "ERROR: Missing -- separator."
    exit 1
fi

# Patterns = all before --
PATTERN=("${@:1:$SEP_INDEX-1}")

# Keywords = all after --
KEYWORDS=("${@:$SEP_INDEX+1}")

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORKSPACE="$ROOT_DIR/workspace"

if [[ ! -d "$WORKSPACE" ]]; then
    echo "ERROR: workspace/ not found in $ROOT_DIR"
    exit 1
fi

echo "[INFO] Searching transcripts..."

# Build regex from all pattern parts
SEARCH_REGEX="$(printf "%s.*" "${PATTERN[@]}")"
SEARCH_REGEX="${SEARCH_REGEX%.*}"

# Find matching transcript folder
MATCHED_FILE=""
LECTURE_NAME=""

for job in $(ls "$WORKSPACE"); do
    if [[ "$job" =~ $SEARCH_REGEX ]]; then
        t=$(find "$WORKSPACE/$job" -maxdepth 1 -type f -name "transcript.txt" | head -n 1)
        if [[ -n "$t" ]]; then
            MATCHED_FILE="$t"
            LECTURE_NAME="$job"
            break
        fi
    fi
done

if [[ -z "$MATCHED_FILE" ]]; then
    echo "ERROR: No transcript matches lecture pattern: ${PATTERN[*]}"
    exit 1
fi

echo "[INFO] Using transcript: $MATCHED_FILE"

# ============================
# OUTPUT FILES FOR THIS LECTURE
# ============================
OUT_TXT="$BLOCK_DIR/${LECTURE_NAME}.txt"
OUT_MD="$BLOCK_DIR/${LECTURE_NAME}.md"

touch "$OUT_TXT"
touch "$OUT_MD"

# ============================
# DEDUP FUNCTION (80% MATCH)
# ============================
similarity() {
    local A="$1"
    local B="$2"
    local lenA="${#A}"
    local lenB="${#B}"
    local maxlen=$(( lenA > lenB ? lenA : lenB ))
    [[ $maxlen -eq 0 ]] && echo 0 && return

    local same=$(printf "%s\n%s" "$A" "$B" | sed 'N;s/.\{0,\}\n/&/' | awk '
        {a[NR]=$0}
        END {
            c=0
            for(i=1;i<=length(a[1]);i++){
                if(substr(a[1],i,1)==substr(a[2],i,1)) c++
            }
            print c
        }
    ')
    echo $(( 100 * same / maxlen ))
}

# ============================
# MAIN LOOP
# ============================
BLOCK_ID=1
FILE="$MATCHED_FILE"

for KW in "${KEYWORDS[@]}"; do
    echo
    echo "[INFO] Searching keyword: $KW"

    matches=($(grep -n "$KW" "$FILE" | cut -d: -f1))

    if [[ ${#matches[@]} -eq 0 ]]; then
        echo "[WARN] No occurrences for keyword: $KW"
        continue
    fi

    for line in "${matches[@]}"; do
        before=$DEFAULT_BEFORE
        after=$DEFAULT_AFTER

        while true; do
            start=$((line - before))
            end=$((line + after))
            [[ $start -lt 1 ]] && start=1

            BLOCK_CONTENT="$(sed -n "${start},${end}p" "$FILE")"

            # Check duplicate blocks for this lecture
            if [[ -s "$OUT_TXT" ]]; then
                EXISTING="$(cat "$OUT_TXT")"
                score=$(similarity "$EXISTING" "$BLOCK_CONTENT")

                if (( score >= SIM_THRESHOLD )); then
                    echo "[SKIP] Block @ line $line is ${score}% similar to existing. Auto-skipped."
                    break
                fi
            fi

            echo
            echo "=== MATCH @$line for \"$KW\" ==="
            echo "----- Preview ($before/$after) -----"
            echo "$BLOCK_CONTENT"
            echo "------------------------------------"
            echo "[ENTER] accept"
            echo "[w] widen"
            echo "[n] narrow"
            echo "[m] manual"
            echo "[s] skip"
            echo "[q] quit"

            read -r -p "> " choice

            case "$choice" in
                "")
                    # Save block to TXT
                    {
                        echo "===== ${LECTURE_NAME} (line $line) ====="
                        echo "$BLOCK_CONTENT"
                        echo
                    } >> "$OUT_TXT"

                    # Save block to MD
                    {
                        echo "## ${LECTURE_NAME} – Line $line"
                        echo
                        echo '```text'
                        echo "$BLOCK_CONTENT"
                        echo '```'
                        echo
                    } >> "$OUT_MD"

                    echo "[SAVED] Block added."
                    BLOCK_ID=$((BLOCK_ID+1))
                    break
                    ;;
                w)
                    before=$((before+3))
                    after=$((after+3))
                    ;;
                n)
                    if (( before>2 && after>2 )); then
                        before=$((before-2))
                        after=$((after-2))
                    else
                        echo "Can't narrow further."
                    fi
                    ;;
                m)
                    read -r -p "Enter BEFORE AFTER: " b a
                    before=$b
                    after=$a
                    ;;
                s)
                    echo "[SKIP] Block skipped."
                    break
                    ;;
                q)
                    echo "[QUIT]"
                    exit 0
                    ;;
                *)
                    echo "Invalid."
                    ;;
            esac
        done
    done
done

echo
echo "[DONE] All keywords processed."
echo "[OUT] TXT → $OUT_TXT"
echo "[OUT] MD  → $OUT_MD"