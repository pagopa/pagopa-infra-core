import os
import re
import subprocess
import sys

class bcolors:
  SECTION = '\033[0;30;47m'
  INFO = '\033[1;37;44m'
  WARN = '\033[0;30;43m'
  ERROR = '\033[0;37;41m'
  OK = '\033[0;30;42m'
  ENDC = '\033[0m'
  RED = '\033[91m'
  BLU = '\033[94m'

ordered_folders = {
  # "core": { "prefix": ""},
  # "next-core/next-core-secrets": {"prefix": ""},
  # "next-core/next-core-common": { "prefix": ""},
  # "core-itn/core-itn-secrets": {"prefix": ""},
  # "core-itn/core-itn-common": {"prefix": ""},
  # "network/network-secrets": { "prefix": ""},
  # "network/network-common": { "prefix": ""},
  "aks-platform": { "prefix": "weu", "k8s": True},
  # "next-aks": { "prefix": ""},
  # "aks-leonardo": { "prefix": "itn"},
  # "packer": { "prefix": ""},
  # "synthetic-monitoring": { "prefix": "weu"},
  # "db-security/db-security-common": { "prefix": "", "limit_env": ["dev", "prod"]},
  # "db-security/db-security-configuration": { "prefix": "", "limit_env": ["dev", "prod"]},
  # "audit-logs": { "prefix": "" },
  # "client-certs": { "prefix": "" },
  # "continuos-platform-alerting": { "prefix": "" },
  # "grafana-monitoring": { "prefix": "weu" },
  # "release-notes-agent/rn-agent-secrets": { "prefix": "" },
  # "release-notes-agent/rn-agent-common": { "prefix": "" },
  # "cloudo/cloudo-secrets": { "prefix": ""},
  # "cloudo/cloudo-core": { "prefix": ""},
  # "tf-audit": { "prefix": "weu", "limit_env": ["prod"]}
}


def azure_login():
  # In Azure DevOps AzureCLI@2 the session is already authenticated (usually via service connection).
  # Reuse that session and only fallback to Managed Identity when explicitly requested.
  try:
    run_command(['az', 'account', 'show'])
    print("Azure CLI session already authenticated.")
    return
  except subprocess.CalledProcessError:
    pass

  if os.environ.get('FORCE_AZ_LOGIN_IDENTITY', '').lower() != 'true':
    raise RuntimeError(
      "Azure CLI is not authenticated. Run this script inside an AzureCLI@2 task or set "
      "FORCE_AZ_LOGIN_IDENTITY=true to use managed identity login."
    )

  print("Logging into Azure with Managed Identity...")
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
    print(f"{bcolors.WARN} Warning: check_arguments call not found in other_actions(); no changes made. {bcolors.ENDC}")
    return

  print(f"{bcolors.INFO} Patching {script_path}: removing check_arguments call from other_actions()... {bcolors.ENDC}")
  content = content.replace(original_block, patched_block, 1)
  with open(script_path, 'w') as f:
    f.write(content)


def apply_folder(repo_path, folder, config, env, k8s_config_folder):
  folder_path = os.path.join(repo_path, 'src', folder)
  if not os.path.isdir(folder_path):
    raise FileNotFoundError(f" {bcolors.WARN} Folder not found: {folder_path} {bcolors.ENDC}")

  env_name = f"{config['prefix']}-{env}" if config['prefix'] else env
  k8s_arguments = ['-var', f'k8s_kube_config_path_prefix="{k8s_config_folder}"']
  arguments = ['./terraform.sh', 'plan', env_name]
  if config.get('k8s', False):
    arguments.extend(k8s_arguments)
  run_command_streaming(arguments, cwd=folder_path)


def main():
  env = sys.argv[1]
  k8s_config_folder = sys.argv[2]
  repo_path = "."
  azure_login()
  failed_folders = []
  skipped_folders = []
  total_folders = len(ordered_folders)

  # run command on each folder in order
  for folder_index, (folder, config) in enumerate(ordered_folders.items(), start=1):
    if env in config.get('limit_env', ["dev", "uat", "prod"]):
      try:
        print(f"\n{bcolors.SECTION}=== Applying [{folder_index}/{total_folders}] '{folder}' (env: {env}) ==={bcolors.ENDC}")
        apply_folder(repo_path, folder, config, env, k8s_config_folder)
        print(f"{bcolors.OK} Successfully applied folder {folder_index}/{total_folders} '{folder}' {bcolors.ENDC}")
      except Exception as e:
        failed_folders.append(folder)
        print(f"{bcolors.ERROR} Error applying folder '{folder}': {e} {bcolors.ENDC}")
    else:
      skipped_folders.append(folder)
      print(f"{bcolors.INFO} Skipping '{folder}' for env: '{env}'. Exclusion configured {bcolors.ENDC}")

  # report skipped and failed folders
  if skipped_folders:
    print(f"\n{bcolors.INFO} === Skipped folders ({len(skipped_folders)}) === {bcolors.ENDC}")
    for folder in skipped_folders:
      print(f"{bcolors.BLU} - {folder} {bcolors.ENDC}")

  if failed_folders:
    print(
      f"\n{bcolors.ERROR} === Failed folders ({len(failed_folders)}) === {bcolors.ENDC}")
    for folder, error in failed_folders:
      print(f"{bcolors.RED} - {folder}{bcolors.ENDC}")
    exit(1)

if __name__ == '__main__':
  main()
