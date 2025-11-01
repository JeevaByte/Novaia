# Running the project in WSL

This file explains a simple WSL workflow to run this repository using a Python virtual environment (`.venv`) that you already created or will create in WSL.

1) Open WSL and change directory into the project (example):

   cd /mnt/c/Users/Jeeva/Videos/Novaia-master

2) (Optional) If you haven't created the venv in WSL yet, run the helper to create and install requirements:

   ./scripts/wsl_setup.sh

   - This creates `.venv` in the project root (or use `./scripts/wsl_setup.sh /path/to/your/venv`)
   - It also installs packages from `requirements.txt` if present.

3) Activate the venv and run the project (two options):

   - Manual:
       source .venv/bin/activate
       python bot_manager2.py

   - Using helper script:
       ./scripts/wsl_run.sh            # runs default: bot_manager2.py
       ./scripts/wsl_run.sh -- python whisper_ari.py --your-args

Notes and troubleshooting:
- Ensure you run the scripts from WSL (Ubuntu or other distro). The `.venv` created in WSL will live at a Linux path and contain Linux wheels; do not activate that venv from Windows cmd/PowerShell.
- If you previously created the venv in WSL at a custom path, pass it as the first argument to both scripts, e.g. `./scripts/wsl_setup.sh /home/you/.venv_novaia`.
- If some dependencies require system packages (ffmpeg, libsndfile, etc.), install them in WSL using your distro package manager, e.g. `sudo apt update && sudo apt install -y ffmpeg build-essential`.
- If you prefer a reproducible environment, consider using requirements.txt (already present) and optionally `pip freeze > requirements.txt` after you set up your venv.

If you'd like, I can:
- Run the setup script inside WSL now (if you want me to run commands), or
- Add a simple Makefile or VS Code DevContainer for a more reproducible environment.

## Troubleshooting GKE SSH issues

If you are having trouble connecting to a GKE node using SSH, it might be due to missing SSH keys or incorrect IAM permissions. You can use the `gcloud compute config-ssh` command to automatically configure your SSH keys and settings.

This command will:
- Create a new SSH key if one doesn't exist.
- Add the public key to the project or instance metadata.
- Configure your SSH client to use the new key.

To run the command, simply execute:

```bash
gcloud compute config-ssh
```

This will update your SSH configuration for all GKE nodes in your project. After running this command, you should be able to SSH into your nodes without any issues.