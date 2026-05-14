# Quickstart Deploy

## Overview

This guide walks you through deploying the Sovereign Chat Experience Starter application to your Azure subscription. Choose the deployment environment that best suits your needs.

This template uses **gpt-4o-mini** which may not be available in all Azure regions. Check for [up-to-date region availability](https://learn.microsoft.com/azure/ai-services/openai/concepts/models#standard-deployment-model-availability) and select a region during deployment accordingly.

  * We recommend using **East US** or **Sweden Central**

## Choose Your Deployment Environment

### Environment Comparison

| **Option** | **Best For** | **Prerequisites** |
|------------|--------------|-------------------|
| **GitHub Codespaces** | Quick deployment, no local setup required | GitHub account |
| **VS Code Dev Containers** | Fast deployment with local tools | Docker Desktop, VS Code |
| **Local Environment** | Full control, offline development | All tools individually |

---
<br>
<details>
<summary><b>Option A: GitHub Codespaces</b></summary>
<br>
You can run this template virtually by using GitHub Codespaces. The button will open a web-based VS Code instance in your browser:

1. Open the template (this may take several minutes)
    [![Open in GitHub Codespaces](https://github.com/codespaces/badge.svg)](https://codespaces.new/Azure-Samples/sovereign-chat-experience-starter)
2. Open a terminal window
3. Sign into your Azure account:

    ```shell
     azd auth login --use-device-code
    ```

4. Sign into Azure CLI:

    ```shell
     az login
    ```

5. Provision the Azure resources and deploy your code:

    ```shell
    azd up
    ```

    The interactive setup wizard will guide you through selecting your subscription, AKS configuration, AI mode (mock/create/bring-your-own), and deployment settings.

6. Once deployment completes, `azd` will print the application URL. Open it in your browser to start chatting.

</details>

<br>

<details>
<summary><b>Option B: VS Code Dev Containers</b></summary>
<br>

A related option is VS Code Dev Containers, which will open the project in your local VS Code using the [Dev Containers extension](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers):

1. Start Docker Desktop (install it if not already installed)
2. Open the project:
    [![Open in Dev Containers](https://img.shields.io/static/v1?style=for-the-badge&label=Dev%20Containers&message=Open&color=blue&logo=visualstudiocode)](https://vscode.dev/redirect?url=vscode://ms-vscode-remote.remote-containers/cloneInVolume?url=https://github.com/Azure-Samples/sovereign-chat-experience-starter)
3. In the VS Code window that opens, once the project files show up (this may take several minutes), open a terminal window.
4. Sign into your Azure account:

    ```shell
     azd auth login
    ```

5. Sign into Azure CLI:

    ```shell
     az login
    ```

6. Provision the Azure resources and deploy your code:

    ```shell
    azd up
    ```

7. Configure a CI/CD pipeline:

    ```shell
    azd pipeline config
    ```

</details>
<br>

<details>
<summary><b>Option C: Local Environment</b></summary>
<br>

#### Prerequisites:

* [Node.js 20+](https://nodejs.org/) and npm
* Install [azd](https://aka.ms/install-azd)
  * Windows: `winget install microsoft.azd`
  * Linux: `curl -fsSL https://aka.ms/install-azd.sh | bash`
  * MacOS: `brew tap azure/azd && brew install azd`
* [Python 3.9+](https://www.python.org/downloads/)
* [Git](https://git-scm.com/downloads)
* \[Windows Only\] [PowerShell](https://learn.microsoft.com/powershell/scripting/install/installing-powershell-on-windows) (latest version, with `pwsh.exe` on PATH)

#### Setup Steps:

1. Bring down the template code:

    ```shell
    azd init --template sovereign-chat-experience-starter
    ```

2. Sign into your Azure account:

    ```shell
    azd auth login
    ```

3. Installation:

    ```shell
    npm install

    cd server && npm install && cd ..
    ```

4. Provision and deploy the project to Azure:

    ```shell
    azd up
    ```

    The interactive setup wizard will guide you through selecting your subscription, AKS configuration, AI mode (mock/create/bring-your-own), and deployment settings.

5. Once deployment completes, `azd` will print the application URL. Open it in your browser to start chatting.

6. Configure a CI/CD pipeline:

    ```shell
    azd pipeline config
    ```

#### Local Development

There are two ways to run the app locally without deploying to Azure:

##### Option 1 — Mock Mode (no Azure required)

Runs entirely offline with simulated AI responses. Ideal for UI development.

```bash
# Install frontend dependencies
npm install

# Install server dependencies
cd server && npm install && cd ..

# Copy the environment template and set mock mode
cp server/.env.example server/.env
# Edit server/.env and set DATASOURCES=mock

# Terminal 1: Start the frontend
npm run dev

# Terminal 2: Start the server
cd server && npm run start
```

The frontend runs at `http://localhost:5173` and the server at `http://localhost:3001`.

##### Option 2 — API Mode (connects to Microsoft Foundry)

Uses a real Microsoft Foundry agent for live AI responses.

1. Ensure you are logged in to Azure:

    ```shell
    az login
    ```

2. Configure the server environment:

    ```bash
    cp server/.env.example server/.env
    ```

    Edit `server/.env` and set:

    ```
    DATASOURCES=api
    AI_PROJECT_ENDPOINT=https://<your-resource>.services.ai.azure.com/api/projects/<your-project>
    AI_AGENT_ID=<agent-name>:<version>
    ```

3. Install dependencies and start both processes:

    ```bash
    # Terminal 1: Start the frontend
    npm install
    npm run dev

    # Terminal 2: Start the server
    cd server && npm install && npm run start
    ```

</details>


## Clean Up

To remove all deployed resources:

```shell
azd down
```
