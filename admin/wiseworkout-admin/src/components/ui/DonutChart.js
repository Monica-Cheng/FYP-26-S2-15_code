import React from 'react';

const SIZE = 140;
const STROKE = 20;
const RADIUS = (SIZE - STROKE) / 2;
const CIRCUMFERENCE = 2 * Math.PI * RADIUS;
const GAP = 3; // px of arc left as a surface-color gap between segments

// data: [{ label, value, color }]. Renders a donut with a centered total and
// a legend that always shows the direct value + percentage per slice, so
// identity never depends on color alone.
function DonutChart({ title, data }) {
  const total = data.reduce((sum, d) => sum + (d.value || 0), 0);
  let offset = 0;
  const segments = data
    .filter(d => d.value > 0)
    .map(d => {
      const fraction = total > 0 ? d.value / total : 0;
      const rawLength = fraction * CIRCUMFERENCE;
      const length = Math.max(rawLength - GAP, 0);
      const segment = { ...d, fraction, length, offset };
      offset += rawLength;
      return segment;
    });

  return (
    <div className="wwa-chart-card">
      <div className="wwa-chart-title">{title}</div>
      <div className="wwa-chart-body">
        <svg width={SIZE} height={SIZE} viewBox={`0 0 ${SIZE} ${SIZE}`}>
          <circle
            cx={SIZE / 2} cy={SIZE / 2} r={RADIUS}
            fill="none" stroke="#f3f4f6" strokeWidth={STROKE}
          />
          {segments.map(s => (
            <circle
              key={s.label}
              cx={SIZE / 2} cy={SIZE / 2} r={RADIUS}
              fill="none"
              stroke={s.color}
              strokeWidth={STROKE}
              strokeDasharray={`${s.length} ${CIRCUMFERENCE - s.length}`}
              strokeDashoffset={-s.offset}
              transform={`rotate(-90 ${SIZE / 2} ${SIZE / 2})`}
            >
              <title>{`${s.label}: ${s.value} (${Math.round(s.fraction * 100)}%)`}</title>
            </circle>
          ))}
          <text x="50%" y="47%" textAnchor="middle" className="wwa-chart-center-value">{total}</text>
          <text x="50%" y="63%" textAnchor="middle" className="wwa-chart-center-label">Total</text>
        </svg>
        <div className="wwa-chart-legend">
          {data.map(d => (
            <div key={d.label} className="wwa-chart-legend-row">
              <span className="wwa-chart-swatch" style={{ background: d.color }} />
              <span className="wwa-chart-legend-label">{d.label}</span>
              <span className="wwa-chart-legend-value">
                {d.value} ({total > 0 ? Math.round((d.value / total) * 100) : 0}%)
              </span>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}

export default DonutChart;
