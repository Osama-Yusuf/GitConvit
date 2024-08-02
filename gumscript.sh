#!/bin/bash

FAIL_COLOR="#f14e32"
SUCCESS_COLOR="#2b8a3e"

success_log() {
    gum style --foreground "$SUCCESS_COLOR" "✅ $1"
}

error_log() {
    gum style --foreground "$FAIL_COLOR" "🚫 $1"
}

# Check if the previous command succeeded; if not, exit with a message
check_success() {
    if [ $? -ne 0 ]; then
        error_log "$1"
        exit 1
    fi
}

# Function to check if the current directory is a Git repository
check_git_init() {
    git rev-parse --show-toplevel > /dev/null 2>&1
    check_success "The current directory is not a Git repository."
}

check_ollama() {
    if ! command -v ollama &> /dev/null
    then
        error_log "ollama could not be found. Please install it and try again."
        exit 1
    # now try to curl it
    elif curl --output /dev/null --silent --head --fail http://localhost:11434
    then
        success_log "ollama is running on http://localhost:11434."
    else
        error_log "ollama is not running. Please start it and try again."
        exit 1
    fi
}

# Function to run a command and capture its output
run_command() {
    command_output=$(eval "$1")
    echo "$command_output"
}

# Function to get changed files
get_changed_files() {
    files_changed=$(run_command "git diff --name-only")
    echo "$files_changed"
}

# Function to get git status
get_git_status() {
    git_status=$(run_command "git status --porcelain")
    echo "$git_status"
}

# Function to get file diffs
get_file_diffs() {
    file_diffs=$(run_command "git diff")
    echo "$file_diffs"
}

# Function to generate diffs for untracked and tracked files with no changes
generate_diff_for_untracked_files() {
    local git_status="$1"
    diffs=""

    while IFS= read -r line; do
        status=${line:0:2}
        file=${line:3}
        if [[ $status == "??" || $status == " M" || $status == "A " ]]; then
            diff=$(git diff --no-index /dev/null "$file")
            diffs+="$diff\n"
        fi
    done <<< "$git_status"

    echo -e "$diffs"
}

# Function to generate commit message using the AI model
generate_commit_message() {
    local files_changed="$1"
    local file_diffs="$2"
    local additional_diffs="$3"
    local user_input_prompt="$4"

    combined_diffs="$file_diffs\n$additional_diffs"

    if [ -z "$combined_diffs" ]; then
        error_log "There's no files changed or error in retrieving changed files."
        exit 1
    fi

    # Instruction for the AI model
    instruction="Generate a conventional commit message with emojis based on the changes given below. \
Use the following categories and emojis:
    'docs': '📝',
    'feat': '✨',
    'fix': '🐛',
    'style': '🎨',
    'refactor': '🔨',
    'chore': '🚀',
    'config': '⚙️'
For example: 📝 docs(README.md): add installation method with docker
Please respond with a one-liner commit message, nothing more. Remember to give the commit message directly, starting with the emoji."

    if [ -n "$user_input_prompt" ]; then
        instruction+="\nAdditional context from user: $user_input_prompt"
    fi

    # Prepare the prompt for the AI model
    prompt="$instruction\nChanges:\n$combined_diffs"

    # Save prompt to file
    # echo -e "$prompt" > prompt.txt

    # Make the POST request to the AI model
    response=$(gum spin --title "Generating commit message..." -- curl -s -X POST http://localhost:11434/api/chat \
        -H "Content-Type: application/json" \
        -d "$(jq -n --arg prompt "$prompt" '{"model": "llama3:latest", "messages": [{"role": "user", "content": $prompt}]}')")
    check_success "Failed to make POST request to the AI model."

    # Process response to handle multi-part responses
    response_content=$(echo "$response" | jq -r '.message.content')
    commit_message=$(echo "$response_content" | tr -d '\n')

    echo "$commit_message"
    if [ -z "$commit_message" ]; then
        error_log "Failed to generate commit message."
        exit 1
    fi
}

commit_msg_value() {
    files_changed=$(get_changed_files)
    file_diffs=$(get_file_diffs)
    if [ -z "$file_diffs" ]; then
        git_status=$(get_git_status)
        additional_diffs=$(generate_diff_for_untracked_files "$git_status")
        commit_message=$(generate_commit_message "$files_changed" "$file_diffs" "$additional_diffs" "")
    else
        commit_message=$(generate_commit_message "$files_changed" "$file_diffs" "" "")
    fi
    echo "$commit_message"
}

push() {
    current_branch=$(git branch --show-current)
    current_remote_name=$(git remote -v | awk 'NR==1{print $1}')

    commit_message=$(commit_msg_value)
    if [ -z "$commit_message" ]; then
        error_log "There's no commit message to commit."
        exit 1
    fi

    while true; do
        echo -e "\nCommit message: $commit_message\n"
        option=$(gum choose "Use Commit" "Regenerate" "Add to prompt" "Manual" "Edit" "Exit")
        
        case $option in
            "Use Commit")
                break
                ;;
            "Regenerate")
                echo "🔄 Regenerating commit message..."
                commit_message=$(commit_msg_value)
                ;;
            "Add to prompt")
                user_input_prompt=$(gum input --placeholder "Enter additional input for the AI")
                commit_message=$(generate_commit_message "$files_changed" "$file_diffs" "$additional_diffs" "$user_input_prompt")
                ;;
            "Manual")
                TYPE=$(gum choose "fix" "feat" "docs" "style" "refactor" "test" "chore" "revert")
                SCOPE=$(gum input --placeholder "scope")

                # Since the scope is optional, wrap it in parentheses if it has a value.
                test -n "$SCOPE" && SCOPE="($SCOPE)"

                # Pre-populate the input with the type(scope): so that the user may change it
                SUMMARY=$(gum input --value "$TYPE$SCOPE: " --placeholder "Summary of this change")
                DESCRIPTION=$(gum write --placeholder "Details of this change")

                commit_message="$SUMMARY\n\n$DESCRIPTION"
                break
                ;;
            "Edit")
                commit_message=$(gum input --cursor.foreground=green \
                    --prompt.foreground=green --prompt="" \
                    --placeholder "$commit_message" --value="$commit_message"  \
                    --width=160 )
                echo -e "\nUpdated commit message: $commit_message\n"
                ;;
            "Exit")
                exit 0
                ;;
        esac
    done

    git add . && git commit -m "$commit_message" && git push "$current_remote_name" "$current_branch"
}

main() {
    # check gum
    if ! command -v gum &> /dev/null
    then
        echo "gum could not be found. Please install it and try again."
        exit 1
    fi
    check_ollama
    check_git_init
    git_status=$(get_git_status)
    files_changed=$(get_changed_files)
    if [ -z "$git_status" ] && [ -z "$files_changed" ]; then
        error_log "🚫 No files changed."
        exit 1
    fi
    push
}
main