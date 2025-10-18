{
  config,
  lib,
  pkgs,
  ...
}:
let
  myLib = import ./lib.nix { inherit lib pkgs; };
  format = myLib.plistFormat;

  cfg = config.system.profiles;
  removedProfileIdentifiers = lib.mapAttrsToList (n: _: n) (
    lib.filterAttrs (_: v: v.enable == false) cfg.configuration
  );
  installedProfiles = lib.mapAttrs (_: v: v.path) (
    lib.filterAttrs (_: v: v.enable == true) cfg.configuration
  );
in
{
  options.system.profiles = {
    configuration = lib.mkOption {
      description = ''
        System configuration profiles.
      '';
      default = { };
      type = lib.types.attrsOf (
        lib.types.submodule (
          { name, config, ... }:
          {
            options = {
              enable = lib.mkOption {
                type = lib.types.nullOr lib.types.bool;
                default = null;
                description = ''
                  Whether to enable this profile.
                '';
              };
              path = lib.mkOption {
                type = lib.types.path;
                description = ''
                  Path to the profile file.
                '';
              };
              topLevel = lib.mkOption {
                type = lib.types.submodule {
                  freeformType = format.type;
                  config = {
                    PayloadIdentifier = name;
                    PayloadScope = "System";
                    PayloadType = "Configuration";
                    PayloadVersion = 1;
                    TargetDeviceType = 5;
                  };
                };
                default = { };
              };
              payloads = lib.mkOption {
                type = lib.types.attrsOf (
                  lib.types.submodule {
                    freeformType = format.type;
                    config = {
                      PayloadVersion = 1;
                    };
                  }
                );
                default = { };
              };
            };
            config = {
              path = lib.mkIf (config.payloads != { }) (
                lib.mkDefault (
                  format.generate "${name}.mobileconfig" (
                    lib.recursiveUpdate config.topLevel {
                      PayloadContent = lib.attrValues (
                        lib.mapAttrs (
                          n: v:
                          v
                          // {
                            PayloadUUID = n;
                          }
                        ) config.payloads
                      );
                    }
                  )
                )
              );
            };
          }
        )
      );
    };
  };

  config = {
    system.activationScripts.extraActivation.text = ''
      echo "updating system configuration profiles..." >&2

      ${lib.concatMapStringsSep "\n" (profile: ''
        if test -n "${myLib.installDateForProfileOfUser "_computerlevel" profile}"; then
          echo "removing ${profile}"
          /usr/bin/profiles remove -type configuration -identifier "${profile}" -forced
        fi
      '') removedProfileIdentifiers}

      ${lib.concatMapAttrsStringSep "\n" (n: v: ''
        echo "installing ${n}"
        oldProfileInstallDate="${myLib.installDateForProfileOfUser "_computerlevel" n}"
        /usr/bin/open x-apple.systempreferences:com.apple.Profiles-Settings.extension ${v}
        while test "$oldProfileInstallDate" == "${myLib.installDateForProfileOfUser "_computerlevel" n}"; do
          sleep 1
        done
      '') installedProfiles}
    '';
  };
}
