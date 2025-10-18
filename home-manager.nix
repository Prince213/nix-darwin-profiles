{
  config,
  lib,
  pkgs,
  ...
}:
let
  myLib = import ./lib.nix { inherit lib pkgs; };

  cfg = config.targets.darwin.profiles;
  removedProfileIdentifiers = lib.mapAttrsToList (n: _: n) (
    lib.filterAttrs (_: v: v.enable == false) cfg.configuration
  );
  installedProfiles = lib.mapAttrs (_: v: v.path) (
    lib.filterAttrs (_: v: v.enable == true) cfg.configuration
  );
in
{
  options.targets.darwin.profiles = {
    configuration = lib.mkOption {
      description = ''
        User configuration profiles.
      '';
      default = { };
      type = lib.types.attrsOf (myLib.profileModule "User");
    };
  };

  config = lib.mkIf (removedProfileIdentifiers != [ ] || installedProfiles != { }) {
    assertions = [
      (lib.hm.assertions.assertPlatform "targets.darwin.profiles" pkgs lib.platforms.darwin)
    ];

    home.activation.darwinConfigurationProfiles = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      ${lib.concatMapStringsSep "\n" (profile: ''
        if test -n "${myLib.installDateForProfileOfUser config.home.username profile}"; then
          echo "removing ${profile}"
          run /usr/bin/profiles remove -type configuration -user ${config.home.username} -identifier "${profile}" -forced
        fi
      '') removedProfileIdentifiers}

      ${lib.concatMapAttrsStringSep "\n" (n: v: ''
        echo "installing ${n}"
        oldProfileInstallDate="${myLib.installDateForProfileOfUser config.home.username n}"
        run /usr/bin/open x-apple.systempreferences:com.apple.Profiles-Settings.extension ${v}
        if test ! -v DRY_RUN; then
          while test "$oldProfileInstallDate" == "${myLib.installDateForProfileOfUser config.home.username n}"; do
            sleep 1
          done
        fi
      '') installedProfiles}
    '';
  };
}
