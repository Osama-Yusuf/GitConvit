import * as vscode from 'vscode';
import * as cp from 'child_process';
import axios from 'axios';
import ollama from 'ollama';

const FAIL_COLOR = "#f14e32";
const SUCCESS_COLOR = "#2b8a3e";

function successLog(message: string) {
    vscode.window.showInformationMessage(`✅ ${message}`);
}

function errorLog(message: string) {
    vscode.window.showErrorMessage(`🚫 ${message}`);
}

function checkSuccess(error: any, message: string) {
    if (error) {
        errorLog(message);
        throw new Error(message);
    }
}

function runCommand(command: string, cwd: string): string {
    try {
        return cp.execSync(command, { cwd }).toString();
    } catch (error) {
        checkSuccess(error, `Failed to run command: ${command}`);
        return "";
    }
}

function getWorkspaceFolder(): string {
    const folders = vscode.workspace.workspaceFolders;
    if (!folders) {
        errorLog("No workspace folder found. Please open a folder in VS Code and try again.");
        throw new Error("No workspace folder found.");
    }
    return folders[0].uri.fsPath;
}

function checkGitInit(cwd: string) {
    try {
        runCommand("git rev-parse --show-toplevel", cwd);
    } catch (error) {
        errorLog("The current directory is not a Git repository.");
        throw new Error("The current directory is not a Git repository.");
    }
}

function checkOllama() {
    if (!cp.execSync("command -v ollama")) {
        errorLog("ollama could not be found. Please install it and try again.");
        throw new Error("ollama could not be found.");
    } else if (!cp.execSync("curl --output /dev/null --silent --head --fail http://localhost:11434")) {
        errorLog("ollama is not running. Please start it and try again.");
        throw new Error("ollama is not running.");
    } else {
        successLog("ollama is running on http://localhost:11434.");
    }
}

function getChangedFiles(cwd: string): string {
    return runCommand("git diff --name-only", cwd);
}

function getGitStatus(cwd: string): string {
    return runCommand("git status --porcelain", cwd);
}

function getFileDiffs(cwd: string): string {
    return runCommand("git diff", cwd);
}

function generateDiffForUntrackedFiles(gitStatus: string, cwd: string): string {
    let diffs = "";
    gitStatus.split('\n').forEach((line) => {
        const status = line.slice(0, 2).trim();
        const file = line.slice(3).trim();
        if (status === "??" || status === "M" || status === "A") {
            const diff = runCommand(`git diff --no-index /dev/null "${file}"`, cwd);
            console.log("Untracked file: ", file);
            console.log("Untracked file diff:", diff);
            diffs += diff + "\n";
        }
    });
    return diffs;
}


async function generateCommitMessage(filesChanged: string, fileDiffs: string, additionalDiffs: string, userInputPrompt: string, cwd: string) {
    const combinedDiffs = fileDiffs + "\n" + additionalDiffs;
    if (!combinedDiffs.trim()) {
        errorLog("There's no files changed or error in retrieving changed files.");
        throw new Error("There's no files changed or error in retrieving changed files.");
    }

    console.log("Generated diff:", combinedDiffs);

    const instruction = `Act as a professional developer following conventional commit guidelines.
###Instruction###
Generate a conventional commit message with emojis based on the changes given below. Use the following categories and emojis: 
'docs': '📝', 
'feat': '✨', 
'fix': '🐛', 
'style': '🎨', 
'refactor': '🔨', 
'chore': '🚀', 
'config': '⚙️'. 
For example: 📝 docs(README.md): add installation method with docker. 
Respond with a one-liner commit message directly, Only include the commit msg starting with the emoji.
###Context###
${userInputPrompt ? `Additional context from user: ${userInputPrompt}` : ""}
Changes:\n${combinedDiffs}`;
    try {
        const response = await ollama.chat({
            model: "llama3:latest",
            messages: [{ role: "user", content: instruction }]
        });

        let commitMessage = response.message.content;
        console.log("-=-=-=-=-=-=-=-=-=-=-=-=");
        console.log("Generated commit message:", commitMessage);
        console.log("-=-=-=-=-=-=-=-=-=-=-=-=");

        if (!commitMessage) {
            errorLog("Failed to generate commit message.");
            throw new Error("Failed to generate commit message.");
        }
        return commitMessage;
    } catch (error) {
        console.error("Error making POST request to AI model:", error);
        errorLog("Failed to make POST request to the AI model.");
        throw new Error("Failed to make POST request to the AI model.");
    }
}

async function commitMsgValue(cwd: string): Promise<string> {
    const filesChanged = getChangedFiles(cwd);
    const fileDiffs = getFileDiffs(cwd);
    if (!fileDiffs.trim()) {
        const gitStatus = getGitStatus(cwd);
        const additionalDiffs = generateDiffForUntrackedFiles(gitStatus, cwd);
        return await generateCommitMessage(filesChanged, fileDiffs, additionalDiffs, "", cwd);
    } else {
        return await generateCommitMessage(filesChanged, fileDiffs, "", "", cwd);
    }
}

async function push(cwd: string) {
    const currentBranch = runCommand("git branch --show-current", cwd).trim();
    const currentRemoteName = runCommand("git remote -v | awk 'NR==1{print $1}'", cwd).trim();

    let commitMessage = await commitMsgValue(cwd);
    if (!commitMessage) {
        errorLog("There's no commit message to commit.");
        return;
    }

    while (true) {
        const option = await vscode.window.showQuickPick(["Use Commit", "Regenerate", "Add to prompt", "Manual", "Edit", "Exit"], {
            placeHolder: "Commit message: " + commitMessage
        });

        if (!option || option === "Exit") {
            return;
        }

        switch (option) {
            case "Use Commit":
                break;
            case "Regenerate":
                commitMessage = await commitMsgValue(cwd);
                break;
            case "Add to prompt":
                const userInputPrompt = await vscode.window.showInputBox({ placeHolder: "Enter additional input for the AI" });
                if (userInputPrompt) {
                    commitMessage = await generateCommitMessage(getChangedFiles(cwd), getFileDiffs(cwd), generateDiffForUntrackedFiles(getGitStatus(cwd), cwd), userInputPrompt, cwd);
                }
                break;
            case "Manual":
                const TYPE = await vscode.window.showQuickPick(["fix", "feat", "docs", "style", "refactor", "test", "chore", "revert"], { placeHolder: "Select commit type" });
                if (!TYPE) {
                    errorLog("No commit type selected.");
                    return;
                }
                let SCOPE = await vscode.window.showInputBox({ placeHolder: "scope" });
                if (!SCOPE) {
                    SCOPE = await vscode.window.showQuickPick(["fix", "feat", "docs", "style", "refactor", "test", "chore", "revert"], { placeHolder: "Select scope or enter a new one" });
                }

                SCOPE = SCOPE ? `(${SCOPE})` : "";

                const SUMMARY = await vscode.window.showInputBox({ placeHolder: "Summary of this change", value: `${TYPE}${SCOPE}: ` });
                if (!SUMMARY) {
                    errorLog("No summary provided.");
                    return;
                }

                const DESCRIPTION = await vscode.window.showInputBox({ placeHolder: "Details of this change" });
                if (!DESCRIPTION) {
                    errorLog("No description provided.");
                    return;
                }

                commitMessage = `${SUMMARY}\n\n${DESCRIPTION}`;
                break;
            case "Edit":
                const editedMessage = await vscode.window.showInputBox({ placeHolder: "Edit commit message", value: commitMessage });
                if (editedMessage !== undefined) {
                    commitMessage = editedMessage;
                }
                break;
        }
    }

    runCommand(`git add . && git commit -m "${commitMessage}" && git push ${currentRemoteName} ${currentBranch}`, cwd);
    successLog("Changes have been committed and pushed successfully.");
}

export function activate(context: vscode.ExtensionContext) {
    let disposable = vscode.commands.registerCommand('gitconvit.gitCommitWithAI', async () => {
        const cwd = getWorkspaceFolder();
        if (!cwd) {
            return;
        }
        checkGitInit(cwd);
        checkOllama();
        await push(cwd);
    });

    context.subscriptions.push(disposable);
}

export function deactivate() {}
