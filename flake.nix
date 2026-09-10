{
  description = "Logos monero_wallet_ui — send and receive Monero; balances, history, a reviewed send. Holds no key material.";

  inputs = {
    logos-module-builder.url = "github:logos-co/logos-module-builder";
    monero_wallet_backend = {
      url = "github:logos-co/logos-monero-wallet-backend";
      inputs.logos-module-builder.follows = "logos-module-builder";
    };
    monero_wallet_core_module.follows = "monero_wallet_backend/monero_wallet_core_module";
    monero_node_module.follows = "monero_wallet_backend/monero_node_module";
  };

  outputs = inputs@{ logos-module-builder, ... }:
    logos-module-builder.lib.mkLogosQmlModule {
      src = ./.;
      configFile = ./metadata.json;
      flakeInputs = inputs;
    };
}
