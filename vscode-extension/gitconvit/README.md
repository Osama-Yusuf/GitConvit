# GitConvit

GitConvit is an AI-powered tool that generates conventional commit messages with emojis based on the changes in your Git repository. This tool leverages the `llama3:latest` model from Ollama to create commit messages that follow conventional commit standards, ensuring that your commit history is informative and well-structured.

## Features

- Automatically detects changes in your Git repository.
- Generates conventional commit messages with appropriate emojis.
- Interactive prompts to confirm, regenerate, add input, manually create, or edit the commit message.

## Emojis and Categories

The following categories and emojis are used for generating commit messages:

- `docs`: 📝
- `feat`: ✨
- `fix`: 🐛
- `style`: 🎨
- `refactor`: 🔨
- `chore`: 🚀
- `config`: ⚙️

## Installation

1. **Clone the Repository**:
    ```bash
    git clone https://github.com/Osama-Yusuf/GitConvit.git
    cd GitConvit
    ```

2. **Install Dependencies**:
    ```bash
    npm install
    ```

3. **Ensure Ollama is Running**:
    Make sure you have Ollama installed and running on `http://localhost:11434`.

## Usage

1. **Compile the Extension**:
    ```bash
    npm run compile
    ```

2. **Start Debugging**:
    Press `F5` in the VS Code window where your extension project is open. This will open a new VS Code window with your extension loaded.

3. **Generate Commit Message**:
    - In the new VS Code window, open the Command Palette (`Ctrl+Shift+P` or `Cmd+Shift+P` on macOS).
    - Type `Generate Commit Message with AI` and select it.

### Options

- **Use Commit**: Use the generated commit message.
- **Regenerate**: Regenerate the commit message.
- **Add to Prompt**: Add additional context to the AI prompt.
- **Manual**: Create the commit message manually using predefined types and scopes.
- **Edit**: Edit the generated commit message.
- **Exit**: Exit the prompt without committing.

## Contributing

Contributions are welcome! Please fork the repository and create a pull request with your changes.

## License

This project is licensed under the MIT License. See the LICENSE file for details.

## Contact

For any inquiries or support, please contact [Osama Yusuf](https://github.com/Osama-Yusuf).
