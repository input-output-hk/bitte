{
  _protoConfig,
  pkgs,
  lib,
  config,
  name,
  terranix,
  ...
}: let
  cfg = _protoConfig.cluster;
  isPrem = cfg.infraType == "prem";

  ### Terraform cfg.vbkBackend = "local" parameters:
  #
  # Repo global terraform state branch to use:
  tfBranch = "tf";
  #
  # Encrypted state dir path and file path to use in the repo global terraform state branch.
  # We'll opt to use a `tf` sub-directory so there is clearer separation between
  # the actual terraform state encrypted files which should be committed versus
  # top level branch files which may exist temporarily during terraform operations
  # and should not be committed, such as debug logs, temp plaintext terraform state
  # and other files.  Ideally, these top level dir temp files will be cleaned up
  # by script on each terraform operation, but may remain if a script command breaks.
  encStateDir = "tf/";
  encStatePath = "tf/terraform-${name}.tfstate.enc";
  #
  # A fixed initial commit log msg which will be used to identify terraform branch ownership
  vbkBackendLogSig = "init: Repo global terraform state branch";
  #
  ###

  # encryptedRoot attrs must be declared at the config.* _proto level in the ops/world repos to be accessible here
  relEncryptedFolder = let
    extract = path: lib.last (builtins.split "/nix/store/.{32}-" (toString path));
  in
    if isPrem
    then extract _protoConfig.age.encryptedRoot
    else extract _protoConfig.secrets.encryptedRoot;

  # Avoid a source of potentially confusing sops errors for the end user
  credentialHint = ''{ echo -e "\n\nHINT: Do you need to refresh your environment to obtain valid credentials?\n" 1>&2; false; }'';

  sopsDecrypt = inputType: path:
  # NB: we can't work on store paths that don't yet exist before they are generated
    assert lib.assertMsg (builtins.isString path) "sopsDecrypt: path must be a string ${toString path}";
    "{ sops --decrypt --input-type ${inputType} \"${path}\" || ${credentialHint}; }";

  sopsEncrypt = inputType: outputType: path:
    assert lib.assertMsg (builtins.isString path) "sopsDecrypt: path must be a string ${toString path}";
    "{ sops --encrypt --kms ${toString cfg.kms} --input-type ${inputType} --output-type ${outputType} \"${path}\" || ${credentialHint}; }";

  coreNode =
    if isPrem
    then "${cfg.name}-core-1"
    else "core-1";

  coreNodeCmd =
    if isPrem
    then "ssh"
    else "${pkgs.bitte}/bin/bitte ssh";

  exportPath = ''
    export PATH="${
      with pkgs;
        lib.makeBinPath [
          coreutils
          curl
          gitMinimal
          gnugrep
          gnupg
          jq
          rage
          sops
          terraform-with-plugins
          util-linux
        ]
    }"
  '';

  # Generate declarative TF configuration and copy it to the top level repo dir
  copyTfCfg = ''
    set -euo pipefail
    ${exportPath}

    rm -f config.tf.json
    cp "${config.output}" config.tf.json
    chmod u+rw config.tf.json
  '';

  # Local git startup checks
  localGitStartup = ''
    localGitStartup () {
      # Ensure that local terraform state for workspace $TF_NAME exists
      # Pull all remote updates as we don't know yet which remote we might be using; it might not be origin
      # The time for updating all remote branches seems about the same as updating a single remote branch
      echo "Fetching remote updates..."
      git remote update &> /dev/null

      # Get the current branch and remote via: $BRANCH/$REMOTE
      CMD="$(git rev-parse --abbrev-ref "@{upstream}")"

      # Set git variables used only when vbkBackend is "local"
      BRANCH="''${CMD##*/}"
      REMOTE="''${CMD%%/*}"

      # Assume we DO want to use the TF_BRANCH on the same remote as the current branch
      ENC_STATE_REF="$REMOTE/$TF_BRANCH:$ENC_STATE_PATH"

      # Check if the TF_BRANCH exists using the updated remote information obtained in the command above
      TF_REM_BRANCH_EXISTS="$(git show-branch "remotes/$REMOTE/$TF_BRANCH" &> /dev/null && echo "TRUE" || echo "FALSE" )"

      # Check if the TF_BRANCH exists locally already, as this will modify the worktree commands
      TF_LOC_BRANCH_EXISTS="$(git show-ref -q --verify "refs/heads/$TF_BRANCH" && echo "TRUE" || echo "FALSE" )"

      # Check if the git encrypted state exists
      ENC_STATE_EXISTS="$(git cat-file -e "$ENC_STATE_REF" &> /dev/null && echo "TRUE" || echo "FALSE")"
    }
  '';

  localGitCommonChecks = ''
    localGitCommonChecks () {
      # Check the current branch is not TF_BRANCH.
      # Assume the TF_BRANCH is only used for storing TF state and nothing else.
      STATUS="$([ "$BRANCH" != "$TF_BRANCH" ] && echo "pass" || echo "FAIL")"
      gate "$STATUS" "Terraform local state is stored exclusively in branch $TF_BRANCH.  Please switch to another working branch."

      # Check that a local TF_BRANCH, if it exists, is tracking the expected remote
      if [ "$TF_LOC_BRANCH_EXISTS" = "TRUE" ]; then
        STATUS="$(git rev-list "refs/remotes/$REMOTE/$TF_BRANCH" --quiet && echo "pass" || echo "FAIL")"
      else
        STATUS="pass"
      fi
      MSG=(
        "Terraform local state uses a checkout of branch \"$TF_BRANCH\", but a branch by this name already exists and is tracking an unexpected remote:\n\n"
        "$(git branch -avv | grep "$TF_BRANCH" || true)"
      )
      gate "$STATUS" "$(printf '%s' "''${MSG[@]}")"

      # Check that the TF_BRANCH is not already checked out.
      #
      # For performance, worktrees are utilized using already remote updated local repos.
      # This requires we don't already have the TF_BRANCH checkout out somewhere.
      # Enforcing that no TF_BRANCH is checked out elsewhere prior to TF state operations
      # is probably wise anyway to avoid local state scatter confusion.
      #
      # Since we already know from the check above that we are not currently in the TF_BRANCH,
      # the only other source of checkout would be a worktree.
      STATUS="$(git worktree list | grep "\[$TF_BRANCH]" && echo "FAIL" || echo "pass")"
      MSG=(
        "Terraform local state uses exclusive checkout of branch \"$TF_BRANCH\", but this is already checked out in a worktree at:\n\n"
        "$(git worktree list | grep "\[$TF_BRANCH]" || true)"
      )
      gate "$STATUS" "$(printf '%s' "''${MSG[@]}")"

      # Check that the remote TF_BRANCH, if it exists, contains the expected TF state signature in init TF_BRANCH commit
      if [ "$TF_REM_BRANCH_EXISTS" = "TRUE" ]; then
        STATUS="$([ "$(git log --reverse --pretty=format:%s "remotes/$REMOTE/$TF_BRANCH" | head -n 1)" = "$VBK_BACKEND_LOG_SIG" ] && echo "pass" || echo "FAIL")"
      else
        STATUS="pass"
      fi
      gate "$STATUS" "The remote terraform state branch, \"$TF_BRANCH\", does not contain the expected log signature.  This branch may be in conflict with TF usage."

      if [ "$TF_REM_BRANCH_EXISTS" = "TRUE" ] && [ "$TF_LOC_BRANCH_EXISTS" = "TRUE" ]; then
        # Check if local TF_BRANCH is ahead of remote TF_BRANCH
        COMMITS_AHEAD="$(git rev-list --count "remotes/$REMOTE/$TF_BRANCH..refs/heads/$TF_BRANCH")"
        STATUS="$([ "$COMMITS_AHEAD" = "0" ] && echo "pass" || echo "FAIL")"
        gate "$STATUS" "The local terraform state branch, \"$TF_BRANCH\", is ahead of the remote by $COMMITS_AHEAD commits.  Please review the commit diff and resolve."

        # Check if remote TF_BRANCH is ahead of local TF_BRANCH and if so, ensure local can fast-forward
        COMMITS_BEHIND="$(git rev-list --count "refs/heads/$TF_BRANCH..remotes/$REMOTE/$TF_BRANCH")"
        if [ "$COMMITS_BEHIND" != "0" ]; then
          STATUS="$(git merge-base --is-ancestor "refs/heads/$TF_BRANCH" "remotes/$REMOTE/$TF_BRANCH" && echo "pass" || echo "FAIL")"
        else
          STATUS="pass"
        fi
        gate "$STATUS" "The local terraform state branch, \"$TF_BRANCH\", is behind the remote by $COMMITS_BEHIND commits and cannot fast-forward.  Please review the commit diff and resolve."

        # Check that the local TF_BRANCH does not have uncommitted changes
        STATUS="$([ -z "$(git status --porcelain "refs/head/$TF_BRANCH")" ] && echo "pass" || echo "FAIL")"
        gate "$STATUS" "The local terraform state branch, \"$TF_BRANCH\", has uncommitted changed.  Please review the commit diff and resolve."

      elif [ "$TF_REM_BRANCH_EXISTS" = "FALSE" ] && [ "$TF_LOC_BRANCH_EXISTS" = "TRUE" ]; then
        # Check that local TF_BRANCH doesn't exist without remote, which may indicate a failed migration
        STATUS="FAIL"
        gate "$STATUS" "The local terraform state branch, \"$TF_BRANCH\", exists, but the remote does not.  Please review any diff and resolve."
      fi
    }
  '';

  # Create a worklog file and add trap handling
  # Traps based on:
  # https://unix.stackexchange.com/questions/79648/how-to-trigger-error-using-trap-command
  localWorkLog = ''
    WORKLOG="$(mktemp -t tf-wrapper-logs-XXXXXX)"
    touch "$WORKLOG"

    TRAP_MSG() {
      echo >&2
      echo >&2
      echo >&2 "FAIL: Error or signal detected"
      echo >&2 "      Debug log output may be found at:"
      echo >&2
      echo >&2 "      $WORKLOG"
    }

    unset KILLED_BY

    # Set traps for signals, passing the signal through to the final trap handler
    for SIGNAL in INT QUIT TERM HUP; do
      # shellcheck disable=SC2064
      trap "KILLED_BY=$SIGNAL; exit $((128 + $(kill -l "$SIGNAL")))" "$SIGNAL"
    done

    trap '
      RC="$?"

      # If exiting due to an error RC or KILLED_BY signal, print the trap msg
      if [ "$RC" != "0" ] || [ -n "''${KILLED_BY:-}" ]; then
        TRAP_MSG
      fi

      # If a signal was the source of exit and was intercepted by the above signal traps,
      # re-issue the signal now that the trap msg has been shown, so process parents can
      # also handle the signal appropriately.
      if [ -n "''${KILLED_BY:-}" ]; then
        trap - "$KILLED_BY"
        kill -s "$KILLED_BY" "$$"
      fi

      # If just an otherwise unhealthy exit, exit with the given return code
      [ "$RC" != "0" ] && exit "$RC"

      # Otherwise, no reason to retain the worklog, so clean up and exit cleanly
      rm -f "$WORKLOG"
      exit "$RC"
    ' EXIT
  '';

  # Encrypt local state to the encrypted folder.
  # Use binary encryption instead of json for more compact representation
  # and to reduce information leakage via many unencrypted json keys.
  localStateEncrypt = ''
    if [ "$VBK_BACKEND" = "local" ]; then
      # Only encrypt and git add state if the sha256sums are different indicating a state change
      STATE_SHA256_POST="$(sha256sum "terraform-$TF_NAME.tfstate")"

      if [ "''${STATE_SHA256_PRE%% *}" != "''${STATE_SHA256_POST%% *}" ]; then
        echo "State hash: change detected..."
        echo
        warn "STARTING STATE COMMIT FOR TF WORKSPACE $TF_NAME"
        echo
        echo "Status:"
        echo -n "  Extracting state change details  ..."
        STATE_SERIAL="$(jq -r '.serial' < "terraform-$TF_NAME.tfstate")"
        STATE_DETAIL="$(jq -r '. | "* serial: \(.serial)\n* lineage: \(.lineage)\n* version: \(.version)\n* terraform_version: \(.terraform_version)"' < "terraform-$TF_NAME.tfstate")"
        MSG=(
          "$TF_NAME: tf state updated to serial $STATE_SERIAL\n\n\n"
          "State parameters in this commit:\n"
          "$STATE_DETAIL"
        )
        echo "done"

        ${localWorkLog}

        # Set up a tmp git worktree on the TF_BRANCH
        echo -n "  Create a tmp git worktree        ..."
        WORKTREE="$(mktemp -u -d -t tf-$TF_NAME-$BITTE_NAME-XXXXXX)"
        if [ "$TF_LOC_BRANCH_EXISTS" = "TRUE" ]; then
          {
            git worktree add --checkout "$WORKTREE" "$REMOTE/$TF_BRANCH"
            git -C "$WORKTREE" switch "$TF_BRANCH"
            git -C "$WORKTREE" merge --ff
          } &>> "$WORKLOG"

        elif [ "$TF_LOC_BRANCH_EXISTS" = "FALSE" ]; then
          git worktree add -b "$TF_BRANCH" "$WORKTREE" "$REMOTE/$TF_BRANCH" &>> "$WORKLOG"

        fi
        echo "done"

        # Encrypt the plaintext TF state file
        echo -n "  Encrypting locally               ..."
        if [ "$INFRA_TYPE" = "prem" ]; then
          rage -i secrets-prem/age-bootstrap -a -e "terraform-$TF_NAME.tfstate" > "$WORKTREE/$ENC_STATE_PATH"
        else
          ${sopsEncrypt "binary" "binary" "terraform-$TF_NAME.tfstate"} > "$WORKTREE/$ENC_STATE_PATH"
        fi
        echo "done"

        # Git commit encrypted state
        # echo "Git adding state changes"
        echo -n "  Committing encrypted state       ..."
        {
          git -C "$WORKTREE" add "$WORKTREE/$ENC_STATE_PATH"
          git -C "$WORKTREE" commit --no-verify -m "$(echo -e "$(printf '%s' "''${MSG[@]}")")"
          git -C "$WORKTREE" push -u "$REMOTE" "$TF_BRANCH"
        } &>> "$WORKLOG"
        echo "done"

        # Git cleanup plaintext TF state and worktree
        echo -n "  Cleaning up git state            ..."
        {
          rm -vf "$WORKTREE/terraform-$TF_NAME.tfstate"
          git worktree remove "$WORKTREE"
        } &>> "$WORKLOG"
        echo "done"

        echo
        echo " The diff between the last commit and this one may be viewed with:"
        echo
        echo "  icdiff \\"
        if [ "$INFRA_TYPE" = "prem" ]; then
          echo "  <(git cat-file blob \"$REMOTE/$TF_BRANCH~:$ENC_STATE_PATH\" | rage -i secrets-prem/age-bootstrap -d)"
          echo "  <(git cat-file blob \"$ENC_STATE_REF\" | rage -i secrets-prem/age-bootstrap -d) \\"
        else
          echo "  <(git cat-file blob \"$REMOTE/$TF_BRANCH~:$ENC_STATE_PATH\" | sops -d /dev/stdin)"
          echo "  <(git cat-file blob \"$ENC_STATE_REF\" | sops -d /dev/stdin) \\"
        fi
      else
        echo "State hash: change not detected..."
      fi
    fi
  '';

  # Local plaintext state should be uncommitted and cleaned up routinely
  # as some workspaces contain secrets, ex: hydrate-app
  localStateCleanup = ''
    if [ "$VBK_BACKEND" = "local" ] || [ "$ACTION" = "migrateRemote" ]; then
      echo
      echo "Removing plaintext TF state files in the repo top level directory"
      rm -vf "terraform-$TF_NAME.tfstate"
      rm -vf "terraform-$TF_NAME.tfstate.backup"
    fi
  '';

  migStartStatus = ''
    echo
    echo "Important environment variables"
    echo "  config.cluster.name              = $BITTE_NAME"
    echo "  BITTE_CLUSTER env parameter      = $BITTE_CLUSTER"
    echo
    echo "Important migration variables:"
    echo "  INFRA_TYPE                       = $INFRA_TYPE"
    echo "  VAULT_BACKEND                    = $VAULT_BACKEND"
    echo "  VBK_BACKEND                      = $VBK_BACKEND"
    echo "  VBK_BACKEND_LOG_SIG              = $VBK_BACKEND_LOG_SIG"
    echo "  STATE_ARG                        = ''${STATE_ARG:-remote}"
    echo
    echo "Important path variables:"
    echo "  TOP (gitTopLevelDir)             = $TOP"
    echo "  PWD (currentWorkingDir)          = $PWD"
    echo "  REL_ENCRYPTED_FOLDER             = $REL_ENCRYPTED_FOLDER"
    echo
    echo "Important git variables:"
    echo "  REMOTE                           = $REMOTE"
    echo "  BRANCH                           = $BRANCH"
    echo "  ENC_STATE_EXISTS                 = $ENC_STATE_EXISTS"
    echo "  ENC_STATE_DIR                    = $ENC_STATE_DIR"
    echo "  ENC_STATE_PATH                   = $ENC_STATE_PATH"
    echo "  ENC_STATE_REF                    = $ENC_STATE_REF"
    echo "  TF_BRANCH                        = $TF_BRANCH"
    echo "  TF_NAME                          = $TF_NAME"
    echo "  TF_REM_BRANCH_EXISTS             = $TF_REM_BRANCH_EXISTS"
    echo "  TF_LOC_BRANCH_EXISTS             = $TF_LOC_BRANCH_EXISTS"
    echo
  '';

  migCommonChecks = ''
    warn "PRE-MIGRATION CHECKS:"
    echo
    echo "Status:"

    # Ensure the TF workspace is available for the given infraType
    STATUS="$([ "$INFRA_TYPE" = "prem" ] && [[ "$TF_NAME" =~ ^core$|^clients$|^prem-sim$ ]] && echo "FAIL" || echo "pass")"
    echo "  Infra type workspace check:      = $STATUS"
    gate "$STATUS" "The cluster infraType of \"prem\" cannot use the \"$TF_NAME\" TF workspace."

    # Ensure there is nothing strange with environment and cluster name mismatch that may cause unexpected issues
    STATUS="$([ "$BITTE_NAME" = "$BITTE_CLUSTER" ] && echo "pass" || echo "FAIL")"
    echo "  Cluster name check:              = $STATUS"
    gate "$STATUS" "The nix configured name of the cluster does not match the BITTE_CLUSTER env var."

    # Ensure the migration is being run from the top level of the git repo
    STATUS="$([ "$PWD" = "$TOP" ] && echo "pass" || echo "FAIL")"
    echo "  Current pwd check:               = $STATUS"
    gate "$STATUS" "The vbk migration to local state needs to be run from the top level dir of the git repo."

    # Ensure terraform config for workspace $TF_NAME exists and has file size greater than zero bytes
    STATUS="$([ -s "config.tf.json" ] && echo "pass" || echo "FAIL")"
    echo "  Terraform config check:          = $STATUS"
    gate "$STATUS" "The terraform config.tf.json file for workspace $TF_NAME does not exist or is zero bytes in size."

    # Ensure terraform config for workspace $TF_NAME has expected remote backend state set properly
    STATUS="$([ "$(jq -e -r .terraform.backend.http.address < config.tf.json)" = "$VBK_BACKEND/state/$BITTE_NAME/$TF_NAME" ] && echo "pass" || echo "FAIL")"
    echo "  Terraform remote address check:  = $STATUS"
    gate "$STATUS" "The TF generated remote address does not match the expected declarative address."
  '';

  localPreexistingStateCheck = ''
    localPreexistingStateCheck () {
      # Ensure there is no unknown terraform state in the current directory
      for STATE in terraform*.tfstate terraform*.tfstate.backup; do
        if [ -f "$STATE" ]; then
          echo
          warn "Leftover terraform local state exists in the top level repo directory at:"
          echo
          echo "  $TOP/$STATE"
          echo
          echo "* This may be due to a failed terraform command."
          echo "* Diff may be used to compare leftover state against encrypted-committed state."
          echo "* A diff example command to compare leftover state against encrypted-committed state is:"
          echo
          echo "  icdiff $STATE \\"
          if [ "$INFRA_TYPE" = "prem" ]; then
            echo "  <(git cat-file blob \"$ENC_STATE_REF\" | rage -i secrets-prem/age-bootstrap -d)"
          else
            echo "  <(git cat-file blob \"$ENC_STATE_REF\" | sops -d /dev/stdin)"
          fi
          echo
          echo "* If it is determined that this leftover terraform local state should be committed,"
          echo "  example commands to do so are:"
          echo
          echo "  * First, extract state details and form a default commit message (subtitute this with a different message if needed):"
          echo
          echo "  STATE_SERIAL=\"\$(jq -r '.serial' < \"$STATE\")\""
          printf "%s\n" "  STATE_DETAIL=\"\$(jq -r '. | \"* serial: \(.serial)\\n* lineage: \(.lineage)\\n* version: \(.version)\\n* terraform_version: \(.terraform_version)\"' < \"$STATE\")\""
          echo "  MSG=("
          printf "%s\n" "    \"$TF_NAME: tf state updated to serial \$STATE_SERIAL\\n\\n\\n\""
          printf "%s\n" "    \"State parameters in this commit:\\n\""
          echo "    \"\$STATE_DETAIL\""
          echo "  )"
          echo
          echo "  * Create or utilize an existing env to encrypt plaintext state to and commit from there."
          echo "  * In reaching this error message, you are in the top level repo dir, git remote state has already"
          echo "    been updated and remote terraform branch state has been found to exist."
          echo "  * Local terraform branch state (if it exists) may or may not be fast-forwardable to the git remote,"
          echo "    and may or may not be not checked out."
          echo "  * As an example, for the case that the local branch is already up to date with the remote, is not"
          echo "    checked out, and for which a worktree does not already exist, a temporary worktree is"
          echo "    convienent to use without disrupting current branch activity:"
          echo
          echo "  WORKTREE=\"\$(mktemp -u -d -t tf-$TF_NAME-$BITTE_NAME-XXXXXX)\""
          echo
          echo "  * If a \"$TF_BRANCH\" branch already exists locally (check with: git branch -avv), then:"
          echo
          echo "  git worktree add --checkout \"\$WORKTREE\" \"$REMOTE/$TF_BRANCH\""
          echo "  git -C \"\$WORKTREE\" switch \"$TF_BRANCH\""
          echo "  git -C \"\$WORKTREE\" merge --ff"
          echo
          echo "  * Otherwise, if a \"$TF_BRANCH\" branch does NOT already exist locally:"
          echo
          echo "  git worktree add -b \"$TF_BRANCH\" \"\$WORKTREE\" \"$REMOTE/$TF_BRANCH\""
          echo
          echo "  * Now encrypt the plaintext state and save it to the worktree:"
          echo
          if [ "$INFRA_TYPE" = "prem" ]; then
            echo "    rage -i secrets-prem/age-bootstrap -a -e \"$STATE\" > \"\$WORKTREE/$ENC_STATE_PATH\""
          else
            echo "    sops --encrypt --kms \"${toString cfg.kms}\" \\"
            echo "         --input-type binary --output-type binary \\"
            echo "         \"$STATE\" > \"\$WORKTREE/$ENC_STATE_PATH\""
          fi
          echo
          echo "  * Git add, commit, push and clean up:"
          echo
          echo "  git -C \"\$WORKTREE\" add \"\$WORKTREE/$ENC_STATE_PATH\""
          echo "  git -C \"\$WORKTREE\" commit --no-verify -m \"\$(echo -e \"\$(printf '%s' \"\''${MSG[@]}\")\")\""
          echo "  git -C \"\$WORKTREE\" push -u \"$REMOTE\" \"$TF_BRANCH\""
          echo "  git worktree remove \"\$WORKTREE\""
          echo "  rm -vf \"$STATE\""
          echo
          echo "* After all necessary state is confirmed to reside in the encrypted-committed state,"
          echo "  then delete this $STATE file and try again."
          echo
          warn "Leftover plaintext TF state should not be committed and should be removed ASAP is it may contain plaintext secrets"
          exit 1
        else
          true
        fi
      done
    }
  '';

  localStatePrep = ''
    localStatePrep () {
      # Removing existing .terraform/terraform.tfstate avoids a backend reconfigure failure
      # or a remote state migration pull which has already been done via the migrateLocal attr.
      #
      # Our deployments do not currently store anything but backend
      # or local state information in this hidden directory tfstate file.
      #
      # Ref: https://stackoverflow.com/questions/70636974/side-effects-of-removing-terraform-folder
      rm -vf .terraform/terraform.tfstate

      if [ "$INFRA_TYPE" = "prem" ]; then
        git cat-file blob "$ENC_STATE_REF" \
        | rage -i secrets-prem/age-bootstrap -d > "terraform-$TF_NAME.tfstate"
      else
        git cat-file blob "$ENC_STATE_REF" \
        | ${sopsDecrypt "binary" "/dev/stdin"} > "terraform-$TF_NAME.tfstate"
      fi

      terraform init -reconfigure 1>&2
      STATE_ARG="-state=terraform-$TF_NAME.tfstate"
      STATE_SHA256_PRE="$(sha256sum "terraform-$TF_NAME.tfstate")"

      # Export to satisfy shell check for non-local codepath var usage.
      export STATE_ARG
      export STATE_SHA256_PRE
    }
  '';

  prepare = ''
    set -euo pipefail
    [ -n "''${TF_DEBUG:-}" ] && set -x
    ${exportPath}

    # Nix interpolated common vars
    # Export to satisfy shell check on the non-local codepath for var usage.
    export BITTE_NAME="${cfg.name}"
    export ENC_STATE_DIR="${encStateDir}"
    ENC_STATE_PATH="${encStatePath}"
    INFRA_TYPE="${cfg.infraType}"
    REL_ENCRYPTED_FOLDER="${relEncryptedFolder}"
    TF_BRANCH="${tfBranch}"
    TF_NAME="${name}"
    VBK_BACKEND="${cfg.vbkBackend}"
    VBK_BACKEND_LOG_SIG="${vbkBackendLogSig}"
    VAULT_BACKEND="${cfg.vaultBackend}"

    # Re-usable functions
    ${localGitStartup}
    ${localPreexistingStateCheck}
    ${localGitCommonChecks}
    ${localStatePrep}

    warn () {
      # Star header len matching the input str len
      printf '*%.0s' $(seq 1 ''${#1})

      echo -e "\n$1"

      # Star footer len matching the input str len
      printf '*%.0s' $(seq 1 ''${#1})
      echo
    }

    gate () {
      [ "$1" = "pass" ] || { echo; echo -e "FAIL: $2"; exit 1; }
    }

    TOP="$(git rev-parse --show-toplevel)"
    PWD="$(pwd)"

    # Ensure this TF operation is being run from the top level of the git repo
    STATUS="$([ "$PWD" = "$TOP" ] && echo "pass" || echo "FAIL")"
    MSG=(
      "The TF attrs need to be run from the top level directory of the repo:\n"
      "  * Top level repo directory is:\n"
      "    $TOP\n\n"
      "  * Current working directory is:\n"
      "    $PWD"
    )
    gate "$STATUS" "$(printf '%s' "''${MSG[@]}")"

    if [ "$TF_NAME" = "hydrate-cluster" ]; then
      if [ "$INFRA_TYPE" = "prem" ]; then
        NOMAD_TOKEN="$(rage -i secrets-prem/age-bootstrap -d "$REL_ENCRYPTED_FOLDER/nomad/nomad.bootstrap.enc.json" | jq -r '.token')"
        VAULT_TOKEN="$(rage -i secrets-prem/age-bootstrap -d "$REL_ENCRYPTED_FOLDER/vault/vault.enc.json" | jq -r '.root_token')"
        CONSUL_HTTP_TOKEN="$(rage -i secrets-prem/age-bootstrap -d "$REL_ENCRYPTED_FOLDER/consul/token-master.age")"
      else
        NOMAD_TOKEN="$(${sopsDecrypt "json" "$REL_ENCRYPTED_FOLDER/nomad.bootstrap.enc.json"} | jq -r '.token')"
        VAULT_TOKEN="$(${sopsDecrypt "json" "$REL_ENCRYPTED_FOLDER/vault.enc.json"} | jq -r '.root_token')"
        CONSUL_HTTP_TOKEN="$(${sopsDecrypt "json" "$REL_ENCRYPTED_FOLDER/consul-core.json"} | jq -r '.acl.tokens.master')"
      fi

      export NOMAD_TOKEN
      export VAULT_TOKEN
      export CONSUL_HTTP_TOKEN
    fi

    # Generate and copy declarative TF state locally for TF to compare to
    ${copyTfCfg}

    if [ "$VBK_BACKEND" = "local" ]; then
      echo "Using local TF state for workspace \"$TF_NAME\"..."

      localGitStartup

      # Ensure that TF_BRANCH exists before proceeding
      STATUS="$([ "$TF_REM_BRANCH_EXISTS" = "TRUE" ] && echo "pass" || echo "FAIL")"
      MSG=(
        "The nix _proto level cluster.vbkBackend option is set to \"local\", however\n"
        "  terraform local state for workspace \"$TF_NAME\" does not exist at:\n\n"
        "    $ENC_STATE_REF\n\n"
        "If all TF workspaces are not yet migrated to local, then:\n"
        "  * Set the cluster.vbkBackend option back to the existing remote backend\n"
        "  * Run the following against each TF workspace that is not yet migrated to local state:\n"
        "    nix run .#clusters.$BITTE_CLUSTER.tf.<TF_WORKSPACE>.migrateLocal\n"
        "  * Finally, set the cluster.vbkBackend option to \"local\""
      )
      gate "$STATUS" "$(printf '%s' "''${MSG[@]}")"

      # Ensure that encrypted state exists before proceeding, re-use the same message as above
      STATUS="$([ "$ENC_STATE_EXISTS" = "TRUE" ] && echo "pass" || echo "FAIL")"
      gate "$STATUS" "$(printf '%s' "''${MSG[@]}")"

      # Check for the most common failure first and provide useful example commands if needed
      localPreexistingStateCheck

      # Check for less common failure modes
      localGitCommonChecks

      # Prepare plaintext state
      localStatePrep
    else
      if [ -z "''${GITHUB_TOKEN:-}" ]; then
        echo
        echo -----------------------------------------------------
        echo ERROR: env variable GITHUB_TOKEN is not set or empty.
        echo Yet, it is required to authenticate before the
        echo utilizing the cluster vault terraform backend.
        echo -----------------------------------------------------
        echo "Please 'export GITHUB_TOKEN=ghp_hhhhhhhh...' using"
        echo your appropriate personal github access token.
        echo -----------------------------------------------------
        exit 1
      fi

      user="''${TF_HTTP_USERNAME:-TOKEN}"
      pass="''${TF_HTTP_PASSWORD:-$( \
        curl -s -d "{\"token\": \"$GITHUB_TOKEN\"}" \
        $VAULT_BACKEND/v1/auth/github-terraform/login \
        | jq -r '.auth.client_token' \
      )}"

      if [ -z "''${TF_HTTP_PASSWORD:-}" ]; then
        echo
        echo -----------------------------------------------------
        echo TIP: you can avoid repetitive calls to the infra auth
        echo api by exporting the following env variables as is.
        echo
        echo The current vault backend in use for TF is:
        echo $VAULT_BACKEND
        echo -----------------------------------------------------
        echo "export TF_HTTP_USERNAME=\"$user\""
        echo "export TF_HTTP_PASSWORD=\"$pass\""
        echo -----------------------------------------------------
      fi

      export TF_HTTP_USERNAME="$user"
      export TF_HTTP_PASSWORD="$pass"

      echo "Using remote TF state for workspace \"$TF_NAME\"..."
      terraform init -reconfigure 1>&2
      STATE_ARG=""
    fi
  '';
in {
  options = {
    configuration = lib.mkOption {
      type = with lib.types;
        submodule {
          imports = [(terranix + "/core/terraform-options.nix")];
        };
    };

    output = lib.mkOption {
      type = lib.mkOptionType {name = "${name}_config.tf.json";};
      apply = v:
        terranix.lib.terranixConfiguration {
          inherit pkgs;
          modules = [config.configuration];
          strip_nulls = false;
        };
    };

    config = lib.mkOption {
      type = lib.mkOptionType {name = "${name}-config";};
      apply = v: pkgs.writeBashBinChecked "${name}-config" copyTfCfg;
    };

    plan = lib.mkOption {
      type = lib.mkOptionType {name = "${name}-plan";};
      apply = v:
        pkgs.writeBashBinChecked "${name}-plan" ''
          ${prepare}
          ACTION="plan"

          terraform plan ''${STATE_ARG:+$STATE_ARG} -out "$TF_NAME.plan" "$@"
          ${localStateCleanup}
        '';
    };

    apply = lib.mkOption {
      type = lib.mkOptionType {name = "${name}-apply";};
      apply = v:
        pkgs.writeBashBinChecked "${name}-apply" ''
          ${prepare}
          ACTION="apply"

          terraform apply ''${STATE_ARG:+$STATE_ARG} "$TF_NAME.plan" "$@"
          ${localStateEncrypt}
          ${localStateCleanup}
        '';
    };

    terraform = lib.mkOption {
      type = lib.mkOptionType {name = "${name}-terraform";};
      apply = v:
        pkgs.writeBashBinChecked "${name}-terraform" ''
          ${prepare}
          ACTION="terraform"

          if [ "$VBK_BACKEND" = "local" ]; then
            ARGS=( "$@" )

            # TF command invocations accepting or requiring local state as indicated by sub-command --help
            TF_SUBCMDS_REQ_LOCAL_STATE=(
              "apply"
              "console"
              "destroy"
              "env"
              "import"
              "output"
              "plan"
              "refresh"
              "taint"
              "untaint"
              "workspace"
              "state"
            )

            # Check if any provided args require or accept local state
            unset SAFETY_SKIP
            for ARG in "''${ARGS[@]}"; do
              if [[ " ''${TF_SUBCMDS_REQ_LOCAL_STATE[*]} " == *" $ARG "* ]]; then

                # If a subcommand accepting or requiring local state is present, check for local state declaration
                if [[ ! " ''${ARGS[*]} " =~ terraform-$TF_NAME.tfstate ]]; then

                  # Warn and exit if local state has not been passed but should be
                  warn "Custom terraform command issued accepts or requires local state declaration"
                  echo
                  echo "  * The custom terraform command issued contains an argument accepting or requiring local state:"
                  echo
                  echo "    terraform $*"
                  echo
                  echo "  * The argument sub-command accepting or requiring local state is: \"$ARG\""
                  echo "  * However, the local decrypted state file for this TF workspace, $TF_NAME, was not passed to the sub-command as an arg:"
                  echo
                  echo "    terraform-$TF_NAME.tfstate"
                  echo
                  echo "  * For most terraform sub-commands accepting or requiring local state, the state declaration is in the following form:"
                  echo
                  echo "    $STATE_ARG"
                  echo
                  echo "  * Otherwise, if you run a terraform command accepting or requiring state and do not provide the local state as an argument, you may lose important state"
                  echo
                  echo "ABORTED"
                  SAFETY_SKIP="true"
                  break
                fi
              fi
            done;
          fi

          # If local plaintext state should have been provided but wasn't, don't run the command to avoid loss of state
          if [ -z "''${SAFETY_SKIP:-}" ]; then
            terraform "$@"
            ${localStateEncrypt}
          fi
          ${localStateCleanup}
        '';
    };

    migrateLocal = lib.mkOption {
      type = lib.mkOptionType {name = "${name}-migrateLocal";};
      apply = v:
        pkgs.writeBashBinChecked "${name}-migrateLocal" ''
          ${prepare}
          export ACTION="migrateLocal"

          warn "TERRAFORM VBK MIGRATION TO *** LOCAL STATE *** FOR $TF_NAME:"

          localGitStartup
          localGitCommonChecks

          ${migStartStatus}
          ${migCommonChecks}

          # Ensure the vbk status is not already local
          STATUS="$([ "$VBK_BACKEND" != "local" ] && echo "pass" || echo "FAIL")"
          echo "  Terraform backend check:         = $STATUS"
          MSG=(
            "The nix _proto level cluster.vbkBackend option is already set to \"local\".\n"
            "If all TF workspaces are not yet migrated to local, then:\n"
            "  * Set the cluster.vbkBackend option back to the existing remote backend\n"
            "  * Run the following against each TF workspace that is not yet migrated to local state:\n"
            "    nix run .#clusters.$BITTE_CLUSTER.tf.<TF_WORKSPACE>.migrateLocal\n\n"
            "  * Finally, set the cluster.vbkBackend option to \"local\"\n"
          )
          gate "$STATUS" "$(printf '%s' "''${MSG[@]}")"

          # Ensure that encrypted terraform state for workspace $TF_NAME does not already exist
          STATUS="$([ "$ENC_STATE_EXISTS" = "FALSE" ] && echo "pass" || echo "FAIL")"
          echo "  Terraform local state presence:  = $STATUS"
          MSG=(
            "Terraform local state for workspace \"$TF_NAME\" appears to already exist at:\n"
            "  $ENC_STATE_REF\n"
          )
          gate "$STATUS" "$(printf '%s' "''${MSG[@]}")"
          echo

          ${localWorkLog}

          warn "STARTING MIGRATION FOR TF WORKSPACE $TF_NAME"
          echo
          echo "Status:"

          # Set up a tmp git worktree on the TF_BRANCH
          WORKTREE="$(mktemp -u -d -t tf-$TF_NAME-$BITTE_NAME-migrate-local-XXXXXX)"
          echo -n "  Create a tmp git worktree        ..."
          if [ "$TF_REM_BRANCH_EXISTS" = "FALSE" ]; then
            {
              git worktree add "$WORKTREE" HEAD
              git -C "$WORKTREE" switch --orphan "$TF_BRANCH"
            } &>> "$WORKLOG"

            {
              echo 'terraform*.tfstate'
              echo 'terraform*.tfstate.backup'
            } > "$WORKTREE/.gitignore"
            git -C "$WORKTREE" add "$WORKTREE/.gitignore" &>> "$WORKLOG"

            {
              echo 'This branch is used for repo global encrypted terraform state'
              echo '* Do NOT commit plaintext terraform state to this branch'
              echo '* Do NOT commit unrelated files to this branch'
              echo '* Do NOT delete this branch'
              echo '* Branch protection rules should be applied to this branch'
            } > "$WORKTREE/README.md"

            {
              git -C "$WORKTREE" add "$WORKTREE/README.md"

              mkdir -p "$WORKTREE/$ENC_STATE_DIR"
              touch "$WORKTREE/$ENC_STATE_DIR/.gitkeep"
              git -C "$WORKTREE" add "$WORKTREE/$ENC_STATE_DIR/.gitkeep"

              git -C "$WORKTREE" commit --no-verify -m "$VBK_BACKEND_LOG_SIG"
              git -C "$WORKTREE" push -u "$REMOTE" "$TF_BRANCH"
            } &>> "$WORKLOG"

          elif [ "$TF_LOC_BRANCH_EXISTS" = "TRUE" ]; then
            {
              git worktree add --checkout "$WORKTREE" "$REMOTE/$TF_BRANCH"
              git -C "$WORKTREE" switch "$TF_BRANCH"
              git -C "$WORKTREE" merge --ff
            } &>> "$WORKLOG"

          elif [ "$TF_LOC_BRANCH_EXISTS" = "FALSE" ]; then
            git worktree add -b "$TF_BRANCH" "$WORKTREE" "$REMOTE/$TF_BRANCH" &>> "$WORKLOG"

          fi
          echo "done"

          # Pull remote state for $TF_NAME to the tmp git worktree
          echo -n "  Fetching remote state            ..."
          terraform state pull > "$WORKTREE/terraform-$TF_NAME.tfstate"
          echo "done"

          echo -n "  Extracting state details         ..."
          STATE_SERIAL="$(jq -r '.serial' < "$WORKTREE/terraform-$TF_NAME.tfstate")"
          STATE_DETAIL="$(jq -r '. | "* serial: \(.serial)\n* lineage: \(.lineage)\n* version: \(.version)\n* terraform_version: \(.terraform_version)"' < "$WORKTREE/terraform-$TF_NAME.tfstate")"
          MSG=(
            "$TF_NAME: tf state migrated to local at serial $STATE_SERIAL\n\n\n"
            "Migrated from remote backend: $VBK_BACKEND\n\n"
            "State parameters in this commit:\n"
            "$STATE_DETAIL"
          )
          echo "done"

          # Encrypt the plaintext TF state file
          echo -n "  Encrypting locally               ..."
          if [ "$INFRA_TYPE" = "prem" ]; then
            rage -i secrets-prem/age-bootstrap -a -e "$WORKTREE/terraform-$TF_NAME.tfstate" > "$WORKTREE/$ENC_STATE_PATH"
          else
            ${sopsEncrypt "binary" "binary" "$WORKTREE/terraform-$TF_NAME.tfstate"} > "$WORKTREE/$ENC_STATE_PATH"
          fi
          echo "done"

          # Git commit encrypted state
          echo -n "  Committing encrypted state       ..."
          {
            git -C "$WORKTREE" add "$WORKTREE/$ENC_STATE_PATH"
            git -C "$WORKTREE" commit --no-verify -m "$(echo -e "$(printf '%s' "''${MSG[@]}")")"
            git -C "$WORKTREE" push -u "$REMOTE" "$TF_BRANCH"
          } &>> "$WORKLOG"
          echo "done"

          # Git cleanup plaintext TF state and worktree
          echo -n "  Cleaning up git state            ..."
          {
            rm -vf "$WORKTREE/terraform-$TF_NAME.tfstate"
            git worktree remove "$WORKTREE"
          } &>> "$WORKLOG"
          echo "done"
          echo

          warn "FINISHED MIGRATION TO LOCAL FOR TF WORKSPACE $TF_NAME"
          echo
          echo "  * The encrypted local state file is found at:"
          echo "    $ENC_STATE_REF"
          echo
          echo "  * Once the local state is confirmed working as expected, the corresponding remote state no longer in use may be deleted:"
          echo "    $VBK_BACKEND/state/$BITTE_NAME/$TF_NAME"
          echo
          echo "  * Decrypt and review with:"
          if [ "$INFRA_TYPE" = "prem" ]; then
            echo "    git cat-file blob \"$ENC_STATE_REF\" | rage -i secrets-prem/age-bootstrap -d"
          else
            echo "    git cat-file blob \"$ENC_STATE_REF\" | sops -d /dev/stdin"
            echo
            echo "NOTE: binary sops encryption is used on the TF state files both for more compact representation"
            echo "      and to avoid unencrypted keys from contributing to an information attack vector."
          fi
          echo
        '';
    };

    migrateRemote = lib.mkOption {
      type = lib.mkOptionType {name = "${name}-migrateRemote";};
      apply = v:
        pkgs.writeBashBinChecked "${name}-migrateRemote" ''
          ${prepare}
          ACTION="migrateRemote"

          warn "TERRAFORM VBK MIGRATION TO *** REMOTE STATE *** FOR $TF_NAME:"

          localGitStartup

          ${migStartStatus}
          ${migCommonChecks}

          # Ensure the vbk status is already remote as the target vbkBackend remote parameter is required
          STATUS="$([ "$VBK_BACKEND" != "local" ] && echo "pass" || echo "FAIL")"
          echo "  Terraform backend check:         = $STATUS"
          MSG=(
            "The nix _proto level cluster.vbkBackend option is already set to \"local\".\n"
            "If all TF workspaces are not yet migrated to remote, then:\n"
            "  * Set the cluster.vbkBackend option to the target migration remote backend, example:\n"
            "    https://vbk.\$FQDN\n\n"
            "  * Run the following against each TF workspace that is not yet migrated to remote state:\n"
            "    nix run .#clusters.$BITTE_CLUSTER.tf.<TF_WORKSPACE>.migrateRemote\n\n"
            "  * Remove the TF local state which is no longer in use at your convienence"
          )
          gate "$STATUS" "$(printf '%s' "''${MSG[@]}")"

          # Ensure that encrypted terraform state for workspace $TF_NAME does already exist
          STATUS="$([ "$ENC_STATE_EXISTS" = "TRUE" ] && echo "pass" || echo "FAIL")"
          echo "  Terraform local state presence:  = $STATUS"
          MSG=(
            "Terraform local state for workspace \"$TF_NAME\" appears to not already exist at:\n"
            "  $ENC_STATE_REF\n"
          )
          gate "$STATUS" "$(printf '%s' "''${MSG[@]}")"

          # Ensure that remote terraform state for workspace $TF_NAME does not already exist
          STATUS="$(terraform state list &> /dev/null && echo "FAIL" || echo "pass")"
          echo "  Terraform remote state presence: = $STATUS"
          MSG=(
            "Terraform remote state for workspace \"$TF_NAME\" appears to already exist at backend vbk path: $VBK_BACKEND/state/$BITTE_NAME/$TF_NAME\n"
            "  * Pushing local TF state to remote will reset the lineage and serial number of the remote state by default\n"
            "  * If this local state still needs to be pushed to this remote:\n"
            "    * Ensure remote state is not needed\n"
            "    * Back it up if desired\n"
            "    * Clear this particular vbk remote state path key\n"
            "    * Try again\n"
            "  * This will ensure lineage conflicts, serial state conflicts, and otherwise unexpected state data loss are not encountered"
          )
          gate "$STATUS" "$(printf '%s' "''${MSG[@]}")"
          echo

          # Check for the most common failure first and provide useful example commands if needed
          localPreexistingStateCheck

          # Check for less common failure modes
          localGitCommonChecks

          # Prepare plaintext state
          localStatePrep
          ${localWorkLog}

          warn "STARTING MIGRATION FOR TF WORKSPACE $TF_NAME"
          echo
          echo "Status:"

          # Push the local state to the remote
          echo -n "  Pushing local state to remote    ..."
          terraform state push "terraform-$TF_NAME.tfstate" &>> "$WORKLOG"
          echo "done"

          ${localStateCleanup}

          echo
          warn "FINISHED MIGRATION TO REMOTE FOR TF WORKSPACE $TF_NAME"
          echo
          echo "  * The new remote state file is found at vbk path:"
          echo "    $VBK_BACKEND/state/$BITTE_NAME/$TF_NAME"
          echo
          echo "  * By default, in this new remote state, terraform will have started a new lineage and reset the serial number"
          echo
          echo "  * The associated encrypted local state no longer in use may now be deleted:"
          echo "    $ENC_STATE_REF"
          echo
        '';
    };
  };
}
