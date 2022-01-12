{ writeBashChecked, coreutils, curl, jq, lib }:

writeBashChecked "generate-aws-ec2-creds.sh" ''
  PATH=${lib.makeBinPath [ coreutils curl jq ]}

  creds_file=$(realpath ~/.aws/credentials)

  # ensure that credentials are correctly placed
  if test -r "$creds_file" && test "$(wc -l < "$creds_file" )" -gt 2; then
    echo "AWS credentials are already present at $creds_file"
    exit 0
  fi

  echo "Creating $creds_file"

  creds=$(curl -X GET http://169.254.169.254/2021-07-15/meta-data/identity-credentials/ec2/security-credentials/ec2-instance)
  access_key=$(echo "$creds" | jq -r '.AccessKeyId')
  secret_access_key=$(echo "$creds" | jq -r '.SecretAccessKey')

  mkdir -vp ~/.aws
  echo "[default]" > "$creds_file"
  echo "aws_access_key_id = $access_key" >> "$creds_file"
  echo "aws_secret_access_key = $secret_access_key" >> "$creds_file"
''
