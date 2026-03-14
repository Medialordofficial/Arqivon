import re

with open("app/lib/providers/live_session_provider.dart", "r") as f:
    content = f.read()

content = re.sub(r'  void _interruptForRecognizedSpeech\(\) \{.*?\n  \}[\n]+  // ── Message handling', '  // ── Message handling', content, flags=re.DOTALL)
content = re.sub(r'\s*_spokenInterruptInFlight = false;\n', '\n', content)
content = re.sub(r'\s*final wasHandledLocally = _spokenInterruptInFlight;\n\s*_spokenInterruptInFlight = false;\n', '\n', content)
content = re.sub(r'if \(wasHandledLocally \|\| !current\.isResponding\) \{', 'if (!current.isResponding) {', content)
content = re.sub(r'\s*if \(current\.isResponding\) \{\n\s*_interruptForRecognizedSpeech\(\);\n\s*\}\n', '\n', content)

with open("app/lib/providers/live_session_provider.dart", "w") as f:
    f.write(content)
