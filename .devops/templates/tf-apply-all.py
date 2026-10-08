import os
import re
import subprocess
import sys

ENV = os.environ.get('ENV', 'dev')

ordered_folders = {
  "network/network-secrets": { "prefix": ""}
}


def azure_login():
  print("Logging into Azure...")
  client_id = os.environ.get('AZURE_CLIENT_ID')
  cmd = ['az', 'login', '--identity']
  if client_id:
    cmd += ['--client-id', client_id]
  run_command(cmd)


def run_command(cmd, cwd=None, env=None):
  result = subprocess.run(
    cmd,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    universal_newlines=True,
    cwd=cwd,
    env=env
  )
  if result.returncode != 0:
    raise subprocess.CalledProcessError(result.returncode, cmd,
                                        output=result.stdout,
                                        stderr=result.stderr)
  return result.stdout


def run_command_streaming(cmd, cwd=None, env=None):
  """Run a command inheriting the parent's stdio, so interactive/streamed
  output (e.g. terraform apply) is visible in real time."""
  result = subprocess.run(cmd, cwd=cwd, env=env)
  if result.returncode != 0:
    raise subprocess.CalledProcessError(result.returncode, cmd,
                                        output=result.stdout,
                                        stderr=result.stderr)






def disable_opa_policy(repo_path):
  """Remove .terraform-opa from the repo root to disable the OPA policy check."""
  opa_marker = os.path.join(repo_path, '.terraform-opa')
  if os.path.isfile(opa_marker):
    print(f"Removing {opa_marker} to disable OPA policy check...")
    os.remove(opa_marker)


def patch_terraform_script(repo_path):
  """Strip the call to check_arguments from other_actions() in scripts/terraform.sh."""
  script_path = os.path.join(repo_path, 'scripts', 'terraform.sh')
  if not os.path.isfile(script_path):
    return

  with open(script_path, 'r') as f:
    content = f.read()

  match = re.search(r'function other_actions\(\)\s*\{.*?\n\}\n', content, re.DOTALL)
  if not match:
    raise RuntimeError("Could not locate other_actions() function in terraform.sh")

  original_block = match.group(0)
  patched_block = re.sub(r'^[ \t]*check_arguments[ \t]*\n', '', original_block, count=1, flags=re.MULTILINE)

  if patched_block == original_block:
    print("Warning: check_arguments call not found in other_actions(); no changes made.")
    return

  print(f"Patching {script_path}: removing check_arguments call from other_actions()...")
  content = content.replace(original_block, patched_block, 1)
  with open(script_path, 'w') as f:
    f.write(content)


def apply_folder(repo_path, folder, prefix, env):
  folder_path = os.path.join(repo_path, 'src', folder)
  if not os.path.isdir(folder_path):
    raise FileNotFoundError(f"Folder not found: {folder_path}")

  env_name = f"{prefix}{ENV}"
  print(f"\n=== Applying '{folder}' (env: {env_name}) in {folder_path} ===")
  run_command_streaming(['./terraform.sh', 'plan', env_name, '-no-color'], cwd=folder_path)


def main():
  env = sys.argv[1]
  repo_path = "."
  azure_login()
  try:
    for folder, config in ordered_folders.items():
      apply_folder(repo_path, folder, config['prefix'], env)
  finally:
    pass  # No cleanup needed


if __name__ == '__main__':
  main()
