{ pkgs, image, regions ? [ "eu-west-1" ], bucket ? "iohk-amis" }:

with pkgs;

writeScript "upload-amis" ''
  #!${stdenv.shell}

  set -e
  export PATH=${lib.makeBinPath [ ec2_ami_tools jq ec2_api_tools awscli qemu ]}:$PATH

  set -o pipefail

  version=${lib.version}-6
  major=${version:0:5}
  echo "NixOS version is $version ($major)"

  stateDir=$HOME/amis/ec2-image-$version/
  mkdir -p $stateDir

  regions="${toString regions}"
  types="hvm"
  stores="ebs"

  for type in $types; do
    imageFile=${image}
    system=x86_64-linux
    arch=x86_64
    for store in $stores; do
      bucket=${bucket}
      bucketDir="$version-$type-$store"

      prevAmi=
      prevRegion=

      for region in $regions; do
        name=nixos-$version-$arch-$type-$store
        description="NixOS $system $version ($type-$store)"

        amiFile=$stateDir/$region.$type.$store.ami-id
        if ! [ -e $amiFile ]; then
          echo "doing $name in $region..."
          if [ -n "$prevAmi" ]; then
            ami=$(aws ec2 copy-image \
              --region "$region" \
              --source-region "$prevRegion" --source-image-id "$prevAmi" \
              --name "$name" --description "$description" | jq -r '.ImageId')
            if [ "$ami" = null ]; then break; fi
          else
            vhdFile=$imageFile
            vhdFileLogicalBytes="$(qemu-img info "$vhdFile" | grep ^virtual\ size: | cut -f 2 -d \(  | cut -f 1 -d \ )"
            vhdFileLogicalGigaBytes=$(((vhdFileLogicalBytes-1)/1024/1024/1024+1)) # Round to the next GB
            echo "Disk size is $vhdFileLogicalBytes bytes. Will be registered as $vhdFileLogicalGigaBytes GB."
            taskId=$(cat $stateDir/$region.$type.task-id 2> /dev/null || true)
            volId=$(cat $stateDir/$region.$type.vol-id 2> /dev/null || true)
            snapId=$(cat $stateDir/$region.$type.snap-id 2> /dev/null || true)

            if [ -z "$snapId" -a -z "$volId" -a -z "$taskId" ]; then
              echo "importing $vhdFile..."
              taskId=$(ec2-import-volume $vhdFile --no-upload -f vhd \
                -O "$AWS_ACCESS_KEY_ID" -W "$AWS_SECRET_ACCESS_KEY" \
                -o "$AWS_ACCESS_KEY_ID" -w "$AWS_SECRET_ACCESS_KEY" \
                --region "$region" -z "''${region}a" \
                --bucket "$bucket" --prefix "$bucketDir/" \
                | tee /dev/stderr \
                | sed 's/.*\(import-vol-[0-9a-z]\+\).*/\1/ ; t ; d')
              echo -n "$taskId" > $stateDir/$region.$type.task-id
            fi

            if [ -z "$snapId" -a -z "$volId" ]; then
              ec2-resume-import  $vhdFile -t "$taskId" --region "$region" \
                -O "$AWS_ACCESS_KEY_ID" -W "$AWS_SECRET_ACCESS_KEY" \
                -o "$AWS_ACCESS_KEY_ID" -w "$AWS_SECRET_ACCESS_KEY"
            fi

            # Wait for the volume creation to finish.
            if [ -z "$snapId" -a -z "$volId" ]; then
              echo "waiting for import to finish..."

              while true; do
                volId=$(aws ec2 describe-conversion-tasks --conversion-task-ids "$taskId" --region "$region" | jq -r .ConversionTasks[0].ImportVolume.Volume.Id)
                done=$(aws ec2 describe-conversion-tasks --conversion-task-ids "$taskId" --region "$region" | jq -r .ConversionTasks[0].State)
                if [ "$done" == completed ]; then break; fi
                echo -n .
                sleep 10
              done
              echo -n "$volId" > $stateDir/$region.$type.vol-id
              aws ec2 create-tags --region $region --resources $volId --tags Key=Rootfs,Value=zfs
            fi
            if [ -n "$volId" -a -n "$taskId" ]; then
              echo "removing import task..."
              ec2-delete-disk-image -t "$taskId" --region "$region" \
                -O "$AWS_ACCESS_KEY_ID" -W "$AWS_SECRET_ACCESS_KEY" \
                -o "$AWS_ACCESS_KEY_ID" -w "$AWS_SECRET_ACCESS_KEY" || true
              rm -f $stateDir/$region.$type.task-id
            fi
            if [ -z "$snapId" ]; then
              echo "creating snapshot..."
              snapId=$(aws ec2 create-snapshot --volume-id "$volId" --region "$region" --description "$description" | jq -r .SnapshotId)
              if [ "$snapId" = null ]; then exit 1; fi
              echo -n "$snapId" > $stateDir/$region.$type.snap-id
              aws ec2 create-tags --region $region --resources $snapId --tags Key=Rootfs,Value=zfs
            fi
            echo "waiting for snapshot to finish..."
            while true; do
              status=$(aws ec2 describe-snapshots --snapshot-ids "$snapId" --region "$region" | jq -r .Snapshots[0].State)
              if [ "$status" = completed ]; then break; fi
              sleep 10
            done
            # Delete the volume
            if [ -n "$volId" ]; then
              echo "deleting volume..."
              aws ec2 delete-volume --volume-id "$volId" --region "$region" || true
              rm -f $stateDir/$region.$type.vol-id
            fi
            blockDeviceMappings="DeviceName=/dev/sda1,Ebs={SnapshotId=$snapId,VolumeSize=$vhdFileLogicalGigaBytes,DeleteOnTermination=true,VolumeType=gp2}"
            extraFlags=""
            extraFlags+=" --root-device-name /dev/sda1"
            extraFlags+=" --sriov-net-support simple"
            extraFlags+=" --ena-support"
            blockDeviceMappings+=" DeviceName=/dev/sdb,VirtualName=ephemeral0"
            blockDeviceMappings+=" DeviceName=/dev/sdc,VirtualName=ephemeral1"
            blockDeviceMappings+=" DeviceName=/dev/sdd,VirtualName=ephemeral2"
            blockDeviceMappings+=" DeviceName=/dev/sde,VirtualName=ephemeral3"
            extraFlags+=" --sriov-net-support simple"
            extraFlags+=" --ena-support"
            extraFlags+=" --virtualization-type hvm"

            ami=$(aws ec2 register-image \
              --name "$name" \
              --description "$description" \
              --region "$region" \
              --architecture "$arch" \
              --block-device-mappings $blockDeviceMappings \
              $extraFlags | jq -r .ImageId)
            if [ "$ami" = null ]; then break; fi
            aws ec2 modify-image-attribute --region $region --image-id $ami --launch-permission "Add=[{Group=all}]"
          fi
          echo -n "$ami" > $amiFile
          echo "created AMI $ami of type '$type' in $region..."
          aws ec2 create-tags --region $region --resources $ami --tags Key=Rootfs,Value=zfs
        else
          ami=$(cat $amiFile)
        fi
        echo "region = $region, type = $type, store = $store, ami = $ami"
        if [ -z "$prevAmi" ]; then
          prevAmi="$ami"
          prevRegion="$region"
        fi
      done
    done
  done
''
