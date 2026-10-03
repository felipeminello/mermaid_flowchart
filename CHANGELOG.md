## 0.1.0

- Initial release.
- `MermaidFlowchart` widget that renders Mermaid `flowchart` / `graph`
  diagrams natively, with `errorBuilder`, `onNodeTap` and semantics.
- Parser for every classic node shape, Mermaid 11 `@{ shape }` nodes, all
  link styles and labels, `&` chaining, nested subgraphs, subgraphs as edge
  endpoints, `classDef`, `class`, `:::`, `style` and `linkStyle`.
- Layered layout with rigid subgraph blocks, straight lanes for long edges
  and orthogonal routing.
- Light and dark palettes, configurable text styles and spacing.
- `FlowchartParser`, `FlowchartLayout` and `FlowchartPainter` exported for
  custom rendering.
