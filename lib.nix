{ lib, pkgs, ... }:
rec {
  # https://github.com/NixOS/nixpkgs/pull/448839
  plistFormat = {
    type =
      let
        plistType =
          with lib.types;
          nullOr (oneOf [
            bool
            int
            float
            str
            path
            (attrsOf plistType)
            (listOf plistType)
          ])
          // {
            description = "Property list (plist) value";
          };
      in
      plistType;
    generate = name: value: pkgs.writeText name (lib.generators.toPlist { escape = true; } value);
  };

  profileModule =
    scope:
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
              freeformType = plistFormat.type;
              config = {
                PayloadIdentifier = name;
                PayloadScope = scope;
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
                freeformType = plistFormat.type;
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
              plistFormat.generate "${name}.mobileconfig" (
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
    );

  valueOfKey = key: type: "/key[.='${key}']/following-sibling::*[1][name()='${type}']";
  dictWithKey =
    key: type: value:
    "/dict[key[.='${key}']/following-sibling::*[1][name()='${type}' and text()='${value}']]";
  profilesOfUser = user: "/plist/dict${valueOfKey user "array"}";
  installDateForProfileOfUser =
    user: profile:
    "$(/usr/bin/profiles list -output stdout-xml | ${lib.getExe' pkgs.libxml2 "xmllint"} --xpath \""
    + "${profilesOfUser user}${dictWithKey "ProfileIdentifier" "string" profile}"
    + "${valueOfKey "ProfileInstallDate" "string"}/text()\" - 2>/dev/null || echo)";
}
