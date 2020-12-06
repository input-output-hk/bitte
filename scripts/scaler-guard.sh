#!/usr/bin/env bash
set -uo pipefail

[ $# -eq 0 ] && { echo "No arguments provided.  Use -h for help."; exit 1; }

while getopts 'amprduenh' c
do
  case "$c" in
    a) ANALYZE="TRUE" ;;
    m) REFERENCE="TRUE" ;;
    p) PROTECT="TRUE" ;;
    r) UNPROTECT="TRUE" ;;
    d) DRAIN="TRUE" ;;
    u) UNDRAIN="TRUE" ;;
    e) ELIGIBLE="TRUE" ;;
    n) UNELIGIBLE="TRUE" ;;
    *)
       echo "This command assists with configuring nomad infrastructure clients for autoscaling scale in or scale out."
       echo "The primary criteria for action on a node by any option is whether there are running allocations or not."
       echo "For customized criteria, the commands used for actions can be viewed by the -m option and carried out manually."
       echo "Appropriate \$NOMAD_TOKEN, \$NOMAD_ADDR and \$AWS_PROFILE vars must already be exported to the environment."
       echo
       echo "usage: $0 [-a] [-m] [-p] [-r] [[-d] [-u] | [-e] [-n]] [-h]"
       echo
       echo "  -a   Analyze nomad clients, but take no action (cannot be used with other options)."
       echo "  -p   Set scale-in protection on any nomad clients running allocations."
       echo "  -r   Remove scale-in protection on any nomad clients not running allocations."
       echo "  -d   Set drain on any nomad clients not running allocations (disables eligibility, cannot be used with eligibility options [-e | -n])."
       echo "  -u   Remove drain on any nomad clients running allocations (enables eligibility, cannot be used with eligibility options [-e | -n])."
       echo "  -e   Add scheduling eligibility for any nomad clients running allocations (cannot be used with drain options [-d | -u])."
       echo "  -n   Remove scheduling eligibility for any nomad clients not running allocations (cannot be used with drain options [-d | -u])."
       echo "  -m   Print a manual CLI reference for executing any actions this script can take manually (cannot be used with other options)."
       echo
       echo
       echo "Example:"
       echo
       echo "    Provide scale-in protection, disable drain, enable eligibility on nomad clients with active allocations"
       echo "    and remove scale-in protection, enable drain, disable eligibility on nomad clients with no active allocations."
       echo
       echo "    $0 -p -d -r -u"
       exit 0
       ;;
  esac
done

[ -z "${NOMAD_TOKEN:-}" ] && { echo "The environmental variable \$NOMAD_TOKEN must be set with a valid admin nomad token.  Use -h for help."; exit 1; }
[ -z "${NOMAD_ADDR:-}" ] && { echo "The environmental variable \$NOMAD_ADDR must be set with a valid nomad API FQDN.  Use -h for help."; exit 1; }
[ -z "${AWS_PROFILE:-}" ] && { echo "The environmental variable \$AWS_PROFILE must be set with a valid AWS profile name for which admin credentials exist.  Use -h for help."; exit 1; }
[ "${ANALYZE:-}" == "TRUE" ] && [ $# -gt 1 ] && { echo "Analyze option cannot be used with any other options.  Use -h for help."; exit 1; }
[ "${REFERENCE:-}" == "TRUE" ] && [ $# -gt 1 ] && { echo "Manual CLI reference option cannot be used with any other options.  Use -h for help."; exit 1; }

if [ "${DRAIN:-}" == "TRUE" ] || [ "${UNDRAIN:-}" == "TRUE" ] && [ "${ELIGIBLE:-}" == "TRUE" ] || [ "${UNELIGIBLE:-}" == "TRUE" ]; then
  echo "Drain options [-d | -u] cannot be specified with eligibility options [-e | -n].  Use -h for help."
  exit 1
fi

# shellcheck disable=SC2016
CURL='curl -s -H "X-Nomad-Token: $NOMAD_TOKEN"'

if [ "${REFERENCE:-}" == "TRUE" ]; then
  echo
  echo "Manual CLI Reference:"
  echo "---------------------"
  echo
  echo -e "Get high level Nomad nodes info:\n"
  echo "    $CURL \"\$NOMAD_ADDR/v1/nodes\""
  echo -e "\n"
  echo -e "Get Nomad nodes FULL_NODE_ID list:\n"
  echo "    $CURL \"\$NOMAD_ADDR/v1/nodes\" \\"
  echo "      | jq -r '.[] | .ID'"
  echo -e "\n"
  echo -e "Get specific Nomad node info (provides drain, eligibility, status, aws instance id, datacenter, public and private ip, etc):\n"
  echo "    $CURL \"\$NOMAD_ADDR/v1/node/\$FULL_NODE_ID\""
  echo -e "\n"
  echo -e "Get specific Nomad node allocation info:\n"
  echo "    $CURL \"\$NOMAD_ADDR/v1/node/\$FULL_NODE_ID/allocations\""
  echo -e "\n"
  echo -e "Get specific Nomad node allocations running count:\n"
  echo "    $CURL \"\$NOMAD_ADDR/v1/node/\$FULL_NODE_ID/allocations\" \\"
  echo "      | jq -r '. | map(select(.DesiredStatus == \"run\")) | length'"
  echo -e "\n"
  echo -e "Get specific aws instance autoscaler info (provides the autoscaler group name, etc):\n"
  echo "    aws --region \"\$NODE_DATACENTER\" autoscaling describe-auto-scaling-instances \\"
  echo "        --instance-ids \"\$NODE_INSTANCE\" \\"
  echo -e "\n"
  echo -e "Set aws instance autoscaler scale-in protection:\n"
  echo "    aws --region \"\$NODE_DATACENTER\" autoscaling set-instance-protection \\"
  echo "        --instance-ids \"\$NODE_INSTANCE\" \\"
  echo "        --auto-scaling-group-name \"\$CLIENT_ASGN\" \\"
  echo "        --protected-from-scale-in"
  echo -e "\n"
  echo -e "Remove aws instance autoscaler scale-in protection:\n"
  echo "    aws --region \"\$NODE_DATACENTER\" autoscaling set-instance-protection \\"
  echo "        --instance-ids \"\$NODE_INSTANCE\" \\"
  echo "        --auto-scaling-group-name \"\$CLIENT_ASGN\" \\"
  echo "        --no-protected-from-scale-in"
  echo -e "\n"
  echo -e "Set Nomad node eligibility for scheduling allocations:\n"
  echo "    nomad node eligibility -enable \"\$FULL_NODE_ID\""
  echo -e "\n"
  echo -e "Remove Nomad node eligibility for scheduling allocations:\n"
  echo "    nomad node eligibility -disable \"\$FULL_NODE_ID\""
  echo -e "\n"
  echo -e "Set Nomad node draining (see command help for more options):\n"
  echo "    nomad node drain -yes -no-deadline -enable \"\$FULL_NODE_ID\""
  echo -e "\n"
  echo -e "Remove Nomad node draining (see command help for more options):\n"
  echo "    nomad node drain -yes -disable \"\$FULL_NODE_ID\""
  echo -e "\n"
  exit 0
fi

COUNT="1"

# Get all nomad client node info
mapfile -t CLIENTS <<< "$(eval "$CURL \"$NOMAD_ADDR/v1/nodes\" | jq -r '.[] | .ID'")"

# Get associated nomad client info
echo "Processing ${#CLIENTS[@]} nomad nodes for information:"
echo
for CLIENT in "${CLIENTS[@]}"; do
  CLIENT_INFO=$(eval "$CURL \"$NOMAD_ADDR/v1/node/${CLIENT}\"")
  CLIENT_ALLOCS=$(eval "$CURL \"$NOMAD_ADDR/v1/node/${CLIENT}/allocations\"")

  CLIENT_INSTANCE=$(jq -r '.Attributes."unique.platform.aws.instance-id"' <<< "$CLIENT_INFO")
  CLIENT_DATACENTER=$(jq -r '.Datacenter' <<< "$CLIENT_INFO")
  CLIENT_DRAIN=$(jq -r '.DRAIN' <<< "$CLIENT_INFO")
  CLIENT_ELIGIBILITY=$(jq -r '.SchedulingEligibility' <<< "$CLIENT_INFO")
  CLIENT_STATUS=$(jq -r '.Status' <<< "$CLIENT_INFO")

  CLIENT_ASI=$(aws --region "$CLIENT_DATACENTER" autoscaling describe-auto-scaling-instances --instance-ids "$CLIENT_INSTANCE")

  CLIENT_PUBLIC_IP=$(jq -r '.Attributes."unique.platform.aws.public-ipv4"' <<< "$CLIENT_INFO")
  CLIENT_PRIVATE_IP=$(jq -r '.Attributes."unique.network.ip-address"' <<< "$CLIENT_INFO")
  CLIENT_ALLOCS_RUNNING=$(jq -r '. | map(select(.DesiredStatus == "run")) | length' <<< "$CLIENT_ALLOCS")
  CLIENT_ASGN=$(jq -r '.AutoScalingInstances | .[0].AutoScalingGroupName' <<< "$CLIENT_ASI")
  CLIENT_AZ=$(jq -r '.AutoScalingInstances | .[0].AvailabilityZone' <<< "$CLIENT_ASI")
  CLIENT_PROTECTION=$(jq -r '.AutoScalingInstances | .[0].ProtectedFromScaleIn' <<< "$CLIENT_ASI")
  CLIENT_TYPE=$(jq -r '.AutoScalingInstances | .[0].InstanceType' <<< "$CLIENT_ASI")

  echo "Nomad Client: $CLIENT (${COUNT} of ${#CLIENTS[@]})"
  echo "    Public IPv4:           $CLIENT_PUBLIC_IP"
  echo "    Private IPv4:          $CLIENT_PRIVATE_IP"
  echo "    AWS Region:            $CLIENT_DATACENTER"
  echo "    AWS Instance:          $CLIENT_INSTANCE"
  echo "    Active Allocs:         $CLIENT_ALLOCS_RUNNING"
  echo "    Autoscaler Group:      $CLIENT_ASGN"
  echo "    Availability Zone:     $CLIENT_AZ"
  echo "    Server Type:           $CLIENT_TYPE"
  echo "    ScaleIn Protection:    $CLIENT_PROTECTION"
  echo "    Nomad Drain:           $CLIENT_DRAIN"
  echo "    Nomad Eligibility:     $CLIENT_ELIGIBILITY"
  echo "    Nomad Status:          $CLIENT_STATUS"
  echo
  if [ "${ANALYZE:-}" == "TRUE" ]; then
    echo "    ANALYZE ONLY -- NO ACTIONS TAKEN"
  else
    echo "    ACTIONS TAKEN:"
    echo
  fi

  # Actions to take based on command line options

  # Set scale in protection on nomad clients with active allocations
  if [ "${PROTECT:-}" == "TRUE" ]; then
    if [[ "$CLIENT_ALLOCS_RUNNING" =~ ^[0-9]+$ ]]; then
      if [ "$CLIENT_ALLOCS_RUNNING" -gt "0" ]; then
        if [ "$CLIENT_PROTECTION" == "true" ]; then
          echo "    ScaleIn Protection:    SKIPPED (already set true)"
        elif [ "$CLIENT_PROTECTION" == "false" ]; then
          if aws --region "$CLIENT_DATACENTER" autoscaling set-instance-protection --instance-ids "$CLIENT_INSTANCE" --auto-scaling-group-name "$CLIENT_ASGN" --protected-from-scale-in; then
            echo "    ScaleIn Protection:    SET_TRUE"
          else
            echo "    ScaleIn Protection:    SET_ERROR (non-zero return value on SET_TRUE)"
          fi
        else
            echo "    ScaleIn Protection:    SET_ERROR (not a member of an auto-scaling group)"
        fi
      else
        echo "    ScaleIn Protection:    SKIPPED (active allocations are equal to 0)"
      fi
    else
      echo "    ScaleIn Protection:    SET_ERROR (active allocations is not a number)"
    fi
  fi

  # Remove scale in protection on nomad clients with zero allocations
  if [ "${UNPROTECT:-}" == "TRUE" ]; then
    if [[ "$CLIENT_ALLOCS_RUNNING" =~ ^[0-9]+$ ]]; then
      if [ "$CLIENT_ALLOCS_RUNNING" -eq "0" ]; then
        if [ "$CLIENT_PROTECTION" == "false" ]; then
          echo "    ScaleIn Protection:    SKIPPED (already set false)"
        elif [ "$CLIENT_PROTECTION" == "true" ]; then
          if aws --region "$CLIENT_DATACENTER" autoscaling set-instance-protection --instance-ids "$CLIENT_INSTANCE" --auto-scaling-group-name "$CLIENT_ASGN" --no-protected-from-scale-in; then
            echo "    ScaleIn Protection:    SET_FALSE"
          else
            echo "    ScaleIn Protection:    SET_ERROR (non-zero return value on SET_FALSE)"
          fi
        else
            echo "    ScaleIn Protection:    SET_ERROR (not a member of an auto-scaling group)"
        fi
      else
        echo "    ScaleIn Protection:    SKIPPED (active allocations are not equal to 0)"
      fi
    else
      echo "    ScaleIn Protection:    SET_ERROR (active allocations is not a number)"
    fi
  fi

  # Set eligilibility on nomad clients with active allocations
  if [ "${ELIGIBLE:-}" == "TRUE" ]; then
    if [[ "$CLIENT_ALLOCS_RUNNING" =~ ^[0-9]+$ ]]; then
      if [ "$CLIENT_ALLOCS_RUNNING" -gt "0" ]; then
        if nomad node eligibility -enable "$CLIENT"; then
          echo "    Nomad Eligibility:     SET_TRUE"
        else
          echo "    Nomad Eligibility:     SET_ERROR (non-zero return value on SET_TRUE)"
        fi
      else
        echo "    Nomad Eligibility:     SKIPPED (active allocations are equal to 0)"
      fi
    else
      echo "    Nomad Eligibility:     SET_ERROR (active allocations is not a number)"
    fi
  fi

  # Remove eligilibility on nomad clients with zero allocations
  if [ "${UNELIGIBLE:-}" == "TRUE" ]; then
    if [[ "$CLIENT_ALLOCS_RUNNING" =~ ^[0-9]+$ ]]; then
      if [ "$CLIENT_ALLOCS_RUNNING" -eq "0" ]; then
        if nomad node eligibility -disable "$CLIENT"; then
          echo "    Nomad Eligibility:     SET_FALSE"
        else
          echo "    Nomad Eligibility:     SET_ERROR (non-zero return value on SET_TRUE)"
        fi
      else
        echo "    Nomad Eligibility:     SKIPPED (active allocations are not equal to 0)"
      fi
    else
      echo "    Nomad Eligibility:     SET_ERROR (active allocations is not a number)"
    fi
  fi

  # Set drain on nomad clients with zero allocations
  if [ "${DRAIN:-}" == "TRUE" ]; then
    if [[ "$CLIENT_ALLOCS_RUNNING" =~ ^[0-9]+$ ]]; then
      if [ "$CLIENT_ALLOCS_RUNNING" -eq "0" ]; then
        if nomad node drain -yes -no-deadline -enable "$CLIENT"; then
          echo "    Nomad Drain:           SET_TRUE"
        else
          echo "    Nomad Drain:           SET_ERROR (non-zero return value on SET_TRUE)"
        fi
      else
        echo "    Nomad Drain:           SKIPPED (active allocations are not equal to 0)"
      fi
    else
      echo "    Nomad Drain:           SET_ERROR (active allocations is not a number)"
    fi
  fi

  # Remove drain on nomad clients with allocations
  if [ "${UNDRAIN:-}" == "TRUE" ]; then
    if [[ "$CLIENT_ALLOCS_RUNNING" =~ ^[0-9]+$ ]]; then
      if [ "$CLIENT_ALLOCS_RUNNING" -gt "0" ]; then
        if nomad node drain -yes -disable "$CLIENT"; then
          echo "    Nomad Drain:           SET_FALSE"
        else
          echo "    Nomad Drain:           SET_ERROR (non-zero return value on SET_FALSE)"
        fi
      else
        echo "    Nomad Drain:           SKIPPED (active allocations are equal to 0)"
      fi
    else
      echo "    Nomad Drain:           SET_ERROR (active allocations is not a number)"
    fi
  fi

  echo
  echo
  COUNT=$((COUNT + 1))
done
echo
echo "    COMPLETED: $((COUNT - 1)) nomad infrastructure clients analyzed"
