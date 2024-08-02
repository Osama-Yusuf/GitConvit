#!/bin/bash

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
    Please respond with a one-liner commit message, nothing more."
    
    # Prepare the prompt for the AI model
    prompt="$instruction\nChanges:\n$file_diffs"
    
    # Save prompt to file
    echo -e "$prompt" > prompt.txt
    
    # Make the POST request to the AI model
    response=$(curl -s -X POST http://localhost:11434/api/chat \
        -H "Content-Type: application/json" \
    -d "$(jq -n --arg prompt "$prompt" '{"model": "llama3:latest", "messages": [{"role": "user", "content": $prompt}]}')")
    
    # Process response to handle multi-part responses
    full_message=$(echo "$response" | jq -r '.message.content' | tr -d '\n')
    
    echo "$full_message"
}

# Main script execution
files_changed=$(get_changed_files)
if [ -n "$files_changed" ]; then
    file_diffs=$(get_file_diffs)
    if [ -n "$file_diffs" ]; then
        commit_message=$(generate_commit_message "$files_changed" "$file_diffs")
        if [ -n "$commit_message" ]; then
            echo "$commit_message"
        fi
    fi
fi
