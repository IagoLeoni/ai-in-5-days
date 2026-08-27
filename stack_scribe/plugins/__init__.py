"""ADK plugins: cross-cutting concerns applied to every agent and tool.

Plugins rather than per-agent callbacks, because a plugin cannot be forgotten at
a call site: it applies app-wide, including to agents added later.
"""

from stack_scribe.plugins.guardrail_plugin import GuardrailPlugin
from stack_scribe.plugins.memory_plugin import AsyncMemoryPlugin
from stack_scribe.plugins.observability_plugin import IntentOutcomePlugin

__all__ = ["AsyncMemoryPlugin", "GuardrailPlugin", "IntentOutcomePlugin"]
