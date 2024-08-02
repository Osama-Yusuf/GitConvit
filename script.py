import subprocess
import requests
import json

def run_command(command):
    try:
        result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True)
        return result.stdout.decode().splitlines()
    except subprocess.CalledProcessError as e:
        print(f"Error running command {' '.join(command)}: {e.stderr.decode()}")
        return []

def get_changed_files():
    # print("Getting changed files...")
    files_changed = run_command(['git', 'diff', '--name-only'])
    if not files_changed:
        print("No files changed or error in retrieving changed files.")
    return files_changed

def get_file_diffs():
    diffs = run_command(['git', 'diff'])
    return diffs

def generate_commit_message(files_changed, file_diffs):
    # print("Generating commit message...")
    # test
    # Instruction for the AI model
    instruction = (
        "Generate a conventional commit message with emojis based on the changes given below. "
        "Use the following categories and emojis:\n"
        "    'docs': '📝',\n"
        "    'feat': '✨',\n"
        "    'fix': '🐛',\n"
        "    'style': '🎨',\n"
        "    'refactor': '🔨',\n"
        "    'chore': '🚀',\n"
        "    'config': '⚙️'\n"
        "For example: 📝 docs(README.md): add installation method with docker\n"
        "Please respond with a one-liner commit message, nothing more.\n"
    )

    # Prepare the prompt for the AI model
    prompt = instruction + "\nChanges:\n" + "\n".join(file_diffs)
    # print(f"Prompt for AI has been saved to prompt.txt")

    # Save prompt to file
    # with open('prompt.txt', 'w') as f:
    #     f.write(prompt)

    response = requests.post(
        'http://localhost:11434/api/chat',
        headers={'Content-Type': 'application/json'},
        data=json.dumps({
            'model': 'llama3:latest',
            'messages': [{'role': 'user', 'content': prompt}]
        })
    )

    # Process response to handle multi-part responses
    response_content = response.content.decode()
    responses = response_content.split('\n')
    full_message = ""
    for part in responses:
        if part:
            try:
                message_part = json.loads(part)
                if 'message' in message_part:
                    full_message += message_part['message']['content']
            except json.JSONDecodeError:
                continue

    commit_message = full_message.strip()
    # print(f"Generated commit message: {commit_message}")
    return commit_message

if __name__ == "__main__":
    files_changed = get_changed_files()
    if files_changed:
        file_diffs = get_file_diffs()
        if file_diffs:
            commit_message = generate_commit_message(files_changed, file_diffs)
            if commit_message:
                print(commit_message)