import React from 'react';

function MetricCard({
  label,
  value,
  meta,
  icon,
  statusTone = 'neutral',
  statusLabel,
  className = '',
}) {
  return (
    <section className={`wwa-metric-card ${className}`.trim()}>
      <div className="wwa-metric-card__top">
        <div className="wwa-metric-card__label">{label}</div>
        {icon ? <div className="wwa-metric-card__icon">{icon}</div> : null}
      </div>
      <div className="wwa-metric-card__value">{value}</div>
      {(meta || statusLabel) ? (
        <div className="wwa-metric-card__footer">
          {meta ? <div className="wwa-metric-card__meta">{meta}</div> : null}
          {statusLabel ? (
            <div className={`wwa-metric-card__status wwa-metric-card__status-${statusTone}`}>{statusLabel}</div>
          ) : null}
        </div>
      ) : null}
    </section>
  );
}

export default MetricCard;
