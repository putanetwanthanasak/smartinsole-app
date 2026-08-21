# Gait Analysis — design notes

Walking-pattern detail screen. Reuses global tokens; everything is rendered
client-side with vanilla SVG (no charting lib) so the prototype stays
single-bundle.

## Sections (top → bottom)

1. **AI classification card** — surfaces the CNN-LSTM verdict and confidence.
2. **Symmetry bar chart** — left vs right stride pressure across last 8 steps.
   Uses brand-primary / brand-accent for L/R so it carries through the app.
3. **Center of Pressure trace** — animated path over a single foot showing
   heel → midfoot → toe. The path uses `stroke-dasharray` to draw on mount.
4. **7-day sparkline + score** — current symmetry score + delta vs week start;
   sparkline is a hand-drawn polyline (no recharts dependency in the runtime).

## Mock numbers

- 8 strides for the symmetry chart, with right foot lagging slightly to make
  the asymmetry verdict legible.
- Last data point of the 7-day trend marks the worst score so the warning tone
  is visible.

Real backend would stream stride data; for the prototype these are static.
