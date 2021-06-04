{ lib, ... }: { services.promtail.enable = lib.mkDefault true; }
