{
  config,
  lib,
  pkgs,
  ...
}:
let
  myLib = import ./lib.nix { inherit lib pkgs; };

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
      type = lib.types.attrsOf (myLib.profileModule "System");
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
