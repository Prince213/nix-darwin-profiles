{
  config,
  lib,
  pkgs,
  ...
}:
let
  myLib = import ./lib.nix { inherit lib pkgs; };
  format = myLib.plistFormat;
in
{
  options.system.profiles = {
    knownProfiles = lib.mkOption {
      description = ''
        List of system profile identifiers owned and managed by nix-darwin.
        Used to indicate what profiles are safe to install/remove based on the configuration.
      '';
      default = [ ];
      type = lib.types.listOf lib.types.str;
    };
    profiles = lib.mkOption {
      description = ''
        System configuration profiles.
      '';
      default = { };
      type = lib.types.attrsOf (
        lib.types.either lib.types.path (
          lib.types.submodule {
            freeformType = format.type;
            config = {
              PayloadType = "Configuration";
              PayloadScope = "System";
              PayloadVersion = 1;
              TargetDeviceType = 5;
            };
          }
        )
      );
    };
  };

  config =
    let
      cfg = config.system.profiles;
      allProfileIdentifiers = lib.attrNames cfg.profiles;
      removedProfileIdentifiers = lib.filter (n: !lib.elem n allProfileIdentifiers) cfg.knownProfiles;
      installedProfileIdentifiers = lib.filter (n: lib.elem n allProfileIdentifiers) cfg.knownProfiles;
      installedProfiles = lib.mapAttrs (
        n: v:
        if lib.isPath v then
          v
        else
          (format.generate "${n}.mobileconfig" (lib.recursiveUpdate v { PayloadIdentifier = n; }))
      ) (lib.filterAttrs (n: _: lib.elem n installedProfileIdentifiers) cfg.profiles);
    in
    {
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
