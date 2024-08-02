#!/bin/bash

# Check if the previous command succeeded; if not, exit with a message
check_success() {
    if [ $? -ne 0 ]; then
        echo "$1"
        exit 1
    fi
}

# Function to check if the current directory is a Git repository
check_git_init() {
    git rev-parse --show-toplevel > /dev/null 2>&1
    check_success "🚫 The current directory is not a Git repository."
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
        echo "🚫 There's no files changed or error in retrieving changed files."
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
    response=$(curl -s -X POST http://localhost:11434/api/chat \
        -H "Content-Type: application/json" \
        -d "$(jq -n --arg prompt "$prompt" '{"model": "llama3:latest", "messages": [{"role": "user", "content": $prompt}]}')")
    check_success "🚫 Failed to make POST request to the AI model."

    # Process response to handle multi-part responses
    response_content=$(echo "$response" | jq -r '.message.content')
    commit_message=$(echo "$response_content" | tr -d '\n')

    echo "$commit_message"
    if [ -z "$commit_message" ]; then
        echo "🚫 Failed to generate commit message."
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
        echo "🚫 There's no commit message to commit."
        exit 1
    fi

    while true; do
        echo -e "\nCommit message: $commit_message\n"
        echo -e "📂 Current directory: ${PWD}\n🌐 Remote: ${current_remote_name}/${current_branch}"
        echo -e "Options: [ENTER to continue, r to regenerate, p to add input, m to manually enter, e to edit, CTRL+C to abort]"
        read -p "Select an option: " user_input

        if [ "$user_input" == "r" ]; then
            echo "🔄 Regenerating commit message..."
            commit_message=$(commit_msg_value)
        elif [ "$user_input" == "p" ]; then
            read -p "📝 Enter additional input for the AI: " user_input_prompt
            commit_message=$(generate_commit_message "$files_changed" "$file_diffs" "$additional_diffs" "$user_input_prompt")
        elif [ "$user_input" == "m" ]; then
            read -p "✍️  Enter the commit message manually: " commit_message
            break
        elif [ "$user_input" == "e" ]; then
            temp_file=$(mktemp)
            echo "# Edit the commit message below. To save and exit press ESC key then ZZ." > "$temp_file"
            echo "$commit_message" >> "$temp_file"
            vim "$temp_file"
            commit_message=$(sed -n '2p' "$temp_file")
            rm "$temp_file"
            echo -e "\nUpdated commit message: $commit_message\n"
            echo -e "Options: [ENTER to continue, r to regenerate, p to add input, m to manually enter, e to edit, CTRL+C to abort]"
            read -p "Select an option: " user_input

            if [ "$user_input" == "r" ] || [ "$user_input" == "p" ] || [ "$user_input" == "m" ]; then
                continue
            else
                break
            fi
        else
            break
        fi
    done

    git add . && git commit -m "$commit_message" && git push "$current_remote_name" "$current_branch"
}

main() {
    check_git_init
    git_status=$(get_git_status)
    files_changed=$(get_changed_files)
    if [ -z "$git_status" ] && [ -z "$files_changed" ]; then
        echo "🚫 No files changed."
        exit 1
    fi
    echo "Generating commit message..."
    push
}

main
