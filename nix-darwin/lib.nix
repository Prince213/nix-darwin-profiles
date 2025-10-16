# https://github.com/NixOS/nixpkgs/pull/448839
{ lib, pkgs, ... }:
rec {
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

  valueOfKey = key: type: "/key[.='${key}']/following-sibling::*[1][name()='${type}']";
  dictWithKey =
    key: type: value:
    "/dict[key[.='${key}']/following-sibling::*[1][name()='${type}' and text()='${value}']]";
  profilesOfUser = user: "/plist/dict${valueOfKey user "array"}";
  installDateForProfileOfUser =
    user: profile:
    "$(/usr/bin/profiles list -output stdout-xml | xmllint --xpath \""
    + "${profilesOfUser user}${dictWithKey "ProfileIdentifier" "string" profile}"
    + "${valueOfKey "ProfileInstallDate" "string"}/text()\" - 2>/dev/null || echo)";
}
