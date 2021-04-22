{ lib, pkgs, ... }: {
  testNomadAutoScaler = pkgs.nixosTest {
    name = "nomad-autoscaler";

    machine = { ... }: {
      imports = [ ../modules/nomad-autoscaler.nix ];

      services.nomad-autoscaler.enable = true;
    };

    testScript = ''
      machine.systemctl("is-system-running --wait")
    '';
  };

  testCeph = pkgs.nixosTest {
    name = "c";

    nodes = let
      common = { pkgs, ... }: {
        virtualisation = {
          memorySize = 512;
          emptyDiskImages = [ 20480 ];
          vlans = [ 1 ];
        };

        imports = [ ../profiles/ceph/default.nix ];
      };

      osd = name: ip: { ... }: {
        imports = [ common ];

        networking.interfaces.eth1.ipv4.addresses = pkgs.lib.mkOverride 0 [{
          address = ip;
          prefixLength = 24;
        }];

        services.ceph = {
          enable = true;
          osd = {
            enable = true;
            daemons = [name];
          };
        };
      };
    in {
      monA = { ... }: {
        imports = [ common ];

        networking = {
          dhcpcd.enable = false;

          interfaces.eth1.ipv4.addresses = pkgs.lib.mkOverride 0 [{
            address = "192.168.1.1";
            prefixLength = 24;
          }];

          firewall = {
            allowedTCPPorts = [ 6789 3300 ];
            allowedTCPPortRanges = [{
              from = 6800;
              to = 7300;
            }];
          };
        };

        services.ceph = {
          enable = true;

          mon = {
            enable = true;
            daemons = [ "monA" ];
          };

          mgr = {
            enable = true;
            daemons = [ "monA" ];
          };
        };
      };

      osd0 = osd "osd0" "192.168.1.2";
      osd1 = osd "osd1" "192.168.1.3";
      osd2 = osd "osd2" "192.168.1.4";
    };

    testScript = ''
      start_all()
      monA.systemctl("is-system-running --wait")
      osd0.systemctl("is-system-running --wait")
      osd1.systemctl("is-system-running --wait")
      osd2.systemctl("is-system-running --wait")

      # monA.log(monA.succeed("ip addr"))
      # osd0.log(monA.succeed("ip addr"))
      # osd1.log(monA.succeed("ip addr"))
      # osd2.log(monA.succeed("ip addr"))

      osd0.succeed(
        "mkfs.xfs /dev/vdb",
        "mkdir -p /var/lib/ceph/osd/ceph-osd0",
        "mount /dev/vdb /var/lib/ceph/osd/ceph-osd0",
        "ceph-authtool --create-keyring /var/lib/ceph/osd/ceph-osd0/keyring --name osd.osd0 --add-key 13e333d9-5cc8-406e-9362-6d0898b687a2",
        'echo \'{"cephx_secret": "AQAU6X9gAagULBAA1pbNfhQpwyJvEVCHiUtVzw=="}\' | ceph osd new 13e333d9-5cc8-406e-9362-6d0898b687a2 -i -',
      )
    '';
  };
}
