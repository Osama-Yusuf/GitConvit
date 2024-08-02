#!/bin/bash

# Check if the previous command succeeded; if not, exit with a message
check_success() {
    if [ $? -ne 0 ]; then
        echo $1
        exit 1
    fi
}

# Function to check if the current directory is a Git repository
check_git_init() {
    git rev-parse --show-toplevel > /dev/null 2>&1
    check_success "The current directory is not a Git repository."
}

# Function to run a command and capture its output
run_command() {
    command_output=$(eval "$1")
    echo "$command_output"
}

# Function to get changed files
get_changed_files() {
    files_changed=$(run_command "git diff --name-only")
    if [ -z "$files_changed" ]; then
        echo "No files changed or error in retrieving changed files."
        exit 1
    fi
    echo "$files_changed"
}

# Function to get file diffs
get_file_diffs() {
    file_diffs=$(run_command "git diff")
    echo "$file_diffs"
}

# Function to generate commit message using the AI model
generate_commit_message() {
    local files_changed=$1
    local file_diffs=$2

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

    # Prepare the prompt for the AI model
    prompt="$instruction\nChanges:\n$file_diffs"

    # Save prompt to file
    echo -e "$prompt" > prompt.txt

    # Make the POST request to the AI model
    response=$(curl -s -X POST http://localhost:11434/api/chat \
        -H "Content-Type: application/json" \
        -d "$(jq -n --arg prompt "$prompt" '{"model": "llama3:latest", "messages": [{"role": "user", "content": $prompt}]}')")
    check_success "Failed to make POST request to the AI model."

    # Process response to handle multi-part responses
    response_content=$(echo "$response" | jq -r '.message.content')
    commit_message=$(echo "$response_content" | tr -d '\n')

    echo "$commit_message"
}

commit_msg_value() {
    files_changed=$(get_changed_files)
    if [ -n "$files_changed" ]; then
        file_diffs=$(get_file_diffs)
        if [ -n "$file_diffs" ]; then
            commit_message=$(generate_commit_message "$files_changed" "$file_diffs")
            if [ -n "$commit_message" ]; then
                echo "$commit_message"
            else
                echo "Failed to generate commit message."
                exit 1
            fi
        fi
    else
        echo "No files changed or error in retrieving changed files."
        exit 1
    fi
}

push() {
    current_branch=$(git branch --show-current)
    current_remote_name=$(git remote -v | awk 'NR==1{print $1}')
    
    while true; do
        commit_message=$(commit_msg_value)
        if [ -z "$commit_message" ]; then
            echo "Failed to generate commit message."
            exit 1
        fi

        echo -e "Commit message: $commit_message\n"
        echo -e "You are currently in: ${PWD}. ${current_remote_name}/${current_branch}"
        read -p "Press Enter to continue, 'r' to recreate the commit message, or CTRL+C to abort: " user_input

        if [ "$user_input" == "r" ]; then
            echo "Recreating commit message..."
        else
            break
        fi
    done
    
    git add . && git commit -m "$commit_message" && git push "$current_remote_name" "$current_branch"
}

main() {
    check_git_init
    push
}

main
