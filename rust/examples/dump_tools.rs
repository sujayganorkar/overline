// Dumps the upstream automation tool catalog as JSON for UX planning:
// `cargo run --example dump_tools`.
fn main() -> Result<(), Box<dyn std::error::Error>> {
    let tools = pdfcraft_automation::tools()
        .into_iter()
        .map(|tool| {
            let properties = tool
                .input_schema
                .get("properties")
                .and_then(|value| value.as_object())
                .map(|map| {
                    map.iter()
                        .map(|(key, value)| {
                            let required = tool
                                .input_schema
                                .get("required")
                                .and_then(|value| value.as_array())
                                .is_some_and(|required| {
                                    required.iter().any(|entry| entry.as_str() == Some(key))
                                });
                            serde_json::json!({
                                "name": key,
                                "type": value.get("type"),
                                "required": required,
                                "description": value.get("description"),
                            })
                        })
                        .collect::<Vec<_>>()
                })
                .unwrap_or_default();
            serde_json::json!({
                "name": tool.name,
                "title": tool.title,
                "description": tool.description,
                "read_only": tool.read_only,
                "destructive": tool.destructive,
                "command": tool.command,
                "args": properties,
            })
        })
        .collect::<Vec<_>>();
    println!("{}", serde_json::to_string_pretty(&tools)?);
    Ok(())
}
