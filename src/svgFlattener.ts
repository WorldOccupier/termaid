const CUSTOM_PROPERTY_DEFINITION = /(--[\w-]+):((?:var\([^)]*\)|[^;"])+)/g;
const VAR_REFERENCE = /var\((--[\w-]+)(?:,([^()]*))?\)/g;

// macOS's SVG renderer (CoreSVG) ignores CSS custom properties, and Pele uses them for every
// color, so diagrams render as black boxes. Substitute each var() with its value or fallback.
export function flattenCssVariables(svg: string): string {
  const definitions = new Map<string, string>();
  for (const [, name, value] of svg.matchAll(CUSTOM_PROPERTY_DEFINITION)) {
    definitions.set(name, value.trim());
  }
  let flattened = svg;
  let previous: string;
  do {
    previous = flattened;
    flattened = flattened.replace(
      VAR_REFERENCE,
      (reference, name: string, fallback?: string) => definitions.get(name) ?? fallback ?? reference,
    );
  } while (flattened !== previous);
  return flattened;
}
