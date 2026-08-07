import React from 'react';

// data: [{ label, value }]. Single-hue magnitude encoding (one measure split
// by an ordinal category, e.g. level) — every bar shares the same color, so
// no legend is needed; the title names what's plotted.
function BarChart({ title, data, color = '#6c63ff' }) {
  const max = Math.max(1, ...data.map(d => d.value));

  return (
    <div className="wwa-chart-card">
      <div className="wwa-chart-title">{title}</div>
      <div className="wwa-bar-chart">
        {data.map(d => (
          <div key={d.label} className="wwa-bar-col">
            <div className="wwa-bar-value">{d.value}</div>
            <div className="wwa-bar-track">
              <div
                className="wwa-bar-fill"
                style={{ height: `${(d.value / max) * 100}%`, background: color }}
                title={`${d.label}: ${d.value}`}
              />
            </div>
            <div className="wwa-bar-label">{d.label}</div>
          </div>
        ))}
      </div>
    </div>
  );
}

export default BarChart;
