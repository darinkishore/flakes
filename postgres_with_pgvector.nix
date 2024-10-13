{
  description = "A demo of Postgres with pgvector and Python/uv support";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    systems.url = "github:nix-systems/default";
    process-compose-flake.url = "github:Platonic-Systems/process-compose-flake";
    services-flake.url = "github:juspay/services-flake";
  };

  outputs =
    inputs:
    inputs.flake-parts.lib.mkFlake { inherit inputs; } {
      systems = import inputs.systems;

      imports = [
        inputs.process-compose-flake.flakeModule
      ];

      perSystem =
        {
          self',
          pkgs,
          config,
          lib,
          ...
        }:
        {

          process-compose."default" =
            { config, ... }:
            let
              dbName = "sample"; # Set the database name
              dbUser = "postgres"; # Set the database user
              dbPassword = "your_secure_password"; # Set the database user password
            in
            {
              imports = [
                inputs.services-flake.processComposeModules.default
              ];

              # PostgreSQL service with pgvector enabled
              services.postgres."pg1" = {
                enable = true;
                superuser = dbUser;
                initialDatabases = [
                  { name = dbName; }
                ];

                # Correctly specify the extensions function
                extensions = (extensions: with extensions; [ pgvector ]);

                # Automatically create pgvector extension in the database
                initialScript.after = ''
                  CREATE EXTENSION IF NOT EXISTS vector;
                  ALTER USER ${dbUser} WITH PASSWORD '${dbPassword}';
                '';

                # Set pg_hba.conf to allow password authentication
                hbaConf = [
                  {
                    type = "local";
                    database = "all";
                    user = "all";
                    address = "";
                    method = "md5";
                  }
                  {
                    type = "host";
                    database = "all";
                    user = "all";
                    address = "0.0.0.0/0";
                    method = "md5";
                  }
                  {
                    type = "host";
                    database = "all";
                    user = "all";
                    address = "::1/128";
                    method = "md5";
                  }
                ];
              };

              # Example service to test PostgreSQL setup with pgvector
              settings.processes.pgweb =
                let
                  pgcfg = config.services.postgres.pg1;
                in
                {
                  environment.PGWEB_DATABASE_URL = "${
                    pgcfg.connectionURI { inherit dbName; }
                  }?user=${dbUser}&password=${dbPassword}";
                  command = pkgs.pgweb;
                  depends_on."pg1".condition = "process_healthy";
                };

              # Test process to validate PostgreSQL is working
              settings.processes.test = {
                command = pkgs.writeShellApplication {
                  name = "pg1-test";
                  runtimeInputs = [ config.services.postgres.pg1.package ];
                  text = ''
                    PGPASSWORD=${dbPassword} echo 'SELECT version();' | psql -h 127.0.0.1 -U ${dbUser} ${dbName}
                  '';
                };
                depends_on."pg1".condition = "process_healthy";
              };
            };

          # Python and uvloop support in the devShell
          devShells.default = pkgs.mkShell {
            nativeBuildInputs = [
              pkgs.just
              pkgs.postgresql
            ];
          };
        };
    };
}
