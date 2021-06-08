{ self, ... }: {
  imports = [ self.inputs.bitte.inputs.hydra-provisioner.nixosModules.default ];
}
