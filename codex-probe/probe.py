def activation_probe_score(events):
    """Return a tiny score for a synthetic activation probe."""
    ready_events = [event for event in events if event.get("status") == "ready"]
    return len(ready_events)


SAMPLE_EVENTS = [
    {"tool": "codex", "status": "ready"},
    {"tool": "codex", "status": "skipped"},
    {"tool": "codex", "status": "ready"},
]


if __name__ == "__main__":
    print(activation_probe_score(SAMPLE_EVENTS))
