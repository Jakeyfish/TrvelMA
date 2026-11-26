// MCP can report an error inside HTTP 200 in either JSON or SSE.
export function successfulFlightResponse(text: string): boolean {
  const events = text.split(/\r?\n/).filter(line => line.startsWith("data:"));
  let hasResult = false;
  for (const payload of events.length ? events.map(line => line.slice(5).trim()) : [text]) {
    try {
      const message = JSON.parse(payload);
      if (message?.error || message?.result?.isError) return false;
      const content = message?.result?.content;
      if (Array.isArray(content)) {
        if (content.some(item => typeof item.text === "string" && /^\s*Error executing tool/i.test(item.text))) return false;
        hasResult ||= content.some(item => {
          if (typeof item.text !== "string") return false;
          const value = item.text.trim();
          return value.length > 0 && !/^(?:\[\s*\]|\{\s*\}|null)$/i.test(value);
        });
      }
      const structured = message?.result?.structuredContent;
      hasResult ||= Boolean(structured && typeof structured === "object" && Object.keys(structured).length > 0);
    } catch { /* Ignore SSE control lines and malformed responses. */ }
  }
  return hasResult;
}
