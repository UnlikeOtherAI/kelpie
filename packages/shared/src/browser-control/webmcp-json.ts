/** Copies only bounded JSON data properties; never invokes getters or toJSON. */
export function boundedWebMcpJson(
  value: unknown,
  limits: { maxBytes: number; maxDepth: number; maxProperties: number; objectOnly?: boolean },
): unknown {
  let properties = 0;
  let bytes = 0;
  const spend = (text: string): void => {
    bytes += new TextEncoder().encode(text).length;
    if (bytes > limits.maxBytes) throw new Error("JSON byte limit");
  };
  const seen = new Set<object>();
  const copy = (item: unknown, depth: number): unknown => {
    if (depth > limits.maxDepth) throw new Error("JSON depth limit");
    if (item === null || typeof item === "boolean") { spend(String(item)); return item; }
    if (typeof item === "number" && Number.isFinite(item)) { spend(String(item)); return item; }
    if (typeof item === "string") {
      if (item.length > limits.maxBytes) throw new Error("JSON string limit");
      spend(JSON.stringify(item));
      return item;
    }
    if (typeof item !== "object" || seen.has(item)) throw new Error("JSON data required");
    const array = Array.isArray(item);
    const prototype: unknown = Object.getPrototypeOf(item);
    if (prototype !== (array ? Array.prototype : Object.prototype) && prototype !== null) throw new Error("Plain JSON data required");
    seen.add(item);
    spend("[]");
    const output: unknown[] | Record<string, unknown> = array ? [] : Object.create(null) as Record<string, unknown>;
    for (const key of Reflect.ownKeys(item)) {
      if (array && key === "length") continue;
      if (typeof key !== "string" || ++properties > limits.maxProperties) throw new Error("JSON property limit");
      const descriptor = Object.getOwnPropertyDescriptor(item, key);
      if (!descriptor || !("value" in descriptor) || !descriptor.enumerable) throw new Error("JSON data properties required");
      if (array && (!/^(0|[1-9][0-9]*)$/.test(key) || Number(key) !== (output as unknown[]).length)) throw new Error("Dense JSON array required");
      spend(array ? "," : JSON.stringify(key) + ":,");
      const copied = copy(descriptor.value, depth + 1);
      if (array) (output as unknown[])[Number(key)] = copied;
      else (output as Record<string, unknown>)[key] = copied;
    }
    seen.delete(item);
    if (array && (output as unknown[]).length !== Object.getOwnPropertyDescriptor(item, "length")?.value) throw new Error("Dense JSON array required");
    return output;
  };
  if (limits.objectOnly && (typeof value !== "object" || value === null || Array.isArray(value))) throw new Error("JSON object required");
  const result = copy(value, 0);
  if (new TextEncoder().encode(JSON.stringify(result)).length > limits.maxBytes) throw new Error("JSON byte limit");
  return result;
}
