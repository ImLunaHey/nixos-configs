{ ... }:
{
  # System defaults apply to SSH and T3's Codex app-server equally. No cloud
  # token is needed: inference stays on this host's loopback interface.
  environment.etc."codex/config.toml".text = ''
    model = "inkling-2-mini-abliterated"
    model_provider = "tower"
    model_context_window = 131072
    model_auto_compact_token_limit = 98304
    model_catalog_json = "/etc/codex/models.json"
    web_search = "disabled"

    [model_providers.tower]
    name = "Tower — Inkling 2 Mini"
    base_url = "http://127.0.0.1:8080/v1"
    wire_api = "responses"
    requires_openai_auth = false
    stream_idle_timeout_ms = 300000
  '';

  environment.etc."codex/models.json".text = builtins.toJSON {
    models = [{
      slug = "inkling-2-mini-abliterated";
      display_name = "Inkling 2 Mini (abliterated, local)";
      description = "AtomicChat IQ3_S on Tower's RTX 5070 Ti; 128K context.";
      base_instructions = "You are a coding assistant. Inspect relevant files, make focused changes, and verify your work using the available tools. Report results accurately and concisely.";
      supported_reasoning_levels = [ ];
      shell_type = "shell_command";
      visibility = "list";
      supported_in_api = true;
      priority = 0;
      support_verbosity = false;
      context_window = 131072;
      input_modalities = [ "text" ];
      truncation_policy = { mode = "tokens"; limit = 8000; };
      experimental_supported_tools = [ ];
    }];
  };
}
