{ pkgs }:
let
  inherit (pkgs) lib;
  releases = lib.importJSON ./releases.json;
  sources = lib.importJSON ./sources.json;
  dependencies = lib.importJSON ./nuget-deps.json;
  nugetSource = pkgs.linkFarm "jellyfin-plugin-nuget-source" (map (dependency: {
    name = "${dependency.pname}.${dependency.version}.nupkg";
    path = pkgs.fetchurl {
      url = "https://api.nuget.org/v3-flatcontainer/${dependency.pname}/${dependency.version}/${dependency.pname}.${dependency.version}.nupkg";
      inherit (dependency) sha256;
    };
  }) dependencies);
  ports = {
    brrr = { name = "brrr.now Notifications"; guid = "a4f8c2d7-1e6b-4c8f-9a3d-7e2f5b8c1d9a"; version = "1.0.1.0"; };
    cinema = { name = "Cinema Mode"; guid = "5fcefe1b-df1f-4596-ac57-f2f939c294c5"; version = "0.6.0.0"; };
    skin = { name = "SkinManager"; guid = "e9ca8b8e-ca6d-40e7-85dc-58e536df8eb3"; version = "2.0.2.0"; };
    listenbrainz = { name = "ListenBrainz"; guid = "59b20823-aafe-454c-a393-17427f518631"; version = "6.6.2.1"; };
  };
  metadata = plugin: pkgs.writeText "meta.json" (builtins.toJSON {
    inherit (plugin) name guid version;
    targetAbi = plugin.targetAbi or "12.0.0.0";
    status = "Active";
    autoUpdate = false;
    description = "Pinned by nixos-configs; update through Nix.";
  });
  fromRelease = plugin: pkgs.runCommand "jellyfin-plugin-${lib.strings.sanitizeDerivationName plugin.name}-${plugin.version}" {
    nativeBuildInputs = [ pkgs.unzip ];
    archive = pkgs.fetchurl { url = plugin.sourceUrl; inherit (plugin) sha256; };
  } ''
    mkdir -p "$out/${plugin.name}_${plugin.version}"
    unzip -q "$archive" -d "$out/${plugin.name}_${plugin.version}"
    cp ${metadata plugin} "$out/${plugin.name}_${plugin.version}/meta.json"
  '';
  fromSource = source:
    let
      plugin = ports.${source.name};
      project = "${lib.optionalString (source.name == "listenbrainz") "src/"}Jellyfin.Plugin.${source.project}/Jellyfin.Plugin.${source.project}.csproj";
    in pkgs.stdenvNoCC.mkDerivation {
      pname = "jellyfin-plugin-${source.name}";
      inherit (plugin) version;
      src = pkgs.fetchurl { inherit (source) url sha256; };
      patches = [ (./. + "/${source.name}.patch") ];
      nativeBuildInputs = [ pkgs.dotnetCorePackages.sdk_10_0 pkgs.esbuild ];
      configurePhase = ''
        runHook preConfigure
        export DOTNET_CLI_HOME="$TMPDIR/dotnet-home"
        mkdir -p "$DOTNET_CLI_HOME"
        export DOTNET_CLI_TELEMETRY_OPTOUT=1
        export DOTNET_SKIP_FIRST_TIME_EXPERIENCE=1
        dotnet restore ${project} --source ${nugetSource} -p:NuGetAudit=false
        runHook postConfigure
      '';
      buildPhase = ''
        runHook preBuild
        ${lib.optionalString (source.name == "listenbrainz") ''
          esbuild src/Jellyfin.Plugin.ListenBrainz/Pages/Configuration/index.ts \
            --bundle --format=esm --target=es2017 \
            --outfile=src/Jellyfin.Plugin.ListenBrainz/Pages/Configuration/index.js
        ''}
        dotnet build ${project} --no-restore -c Release -o output -p:ContinuousIntegrationBuild=true -p:Version=${plugin.version} -p:AssemblyVersion=${plugin.version} -p:FileVersion=${plugin.version}
        runHook postBuild
      '';
      installPhase = ''
        runHook preInstall
        mkdir -p "$out/${plugin.name}_${plugin.version}"
        cp output/Jellyfin.Plugin.${source.project}*.dll "$out/${plugin.name}_${plugin.version}/"
        cp ${metadata plugin} "$out/${plugin.name}_${plugin.version}/meta.json"
        runHook postInstall
      '';
      dontStrip = true;
    };
in pkgs.symlinkJoin {
  name = "jellyfin-12-plugins";
  paths = map fromRelease releases ++ map fromSource sources;
}
