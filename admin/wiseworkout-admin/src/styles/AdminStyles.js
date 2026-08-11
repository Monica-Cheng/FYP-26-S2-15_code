import React from 'react';

// Shared visual language for every admin page (except the Dashboard, which
// keeps its own scoped styles). Mirrors the palette, radii, shadows and
// spacing established on the Dashboard so every page reads as one system.
// Purely presentational — no logic, no data.
export const COLORS = {
  primary: { base: '#6C7EE8', light: '#E6EAFE' },
  cyan: { base: '#4BB8CC', light: '#E0F4F8' },
  green: { base: '#22C55E', light: '#DCFCE7' },
  red: { base: '#EF4444', light: '#FEE2E2' },
  amber: { base: '#F59E0B', light: '#FEF3C7' },
};

function AdminStyles() {
  return (
    <style>{`
      .wwa-page-header {
        display: flex;
        align-items: flex-start;
        justify-content: space-between;
        flex-wrap: wrap;
        gap: var(--ww-space-4);
        margin-bottom: var(--ww-space-6);
        padding-bottom: var(--ww-space-4);
        border-bottom: 1px solid var(--ww-divider);
      }
      .wwa-page-header__content {
        display: flex;
        flex-direction: column;
        gap: 6px;
        min-width: 0;
      }
      .wwa-title {
        font-size: var(--ww-type-page-title-size);
        font-weight: var(--ww-type-page-title-weight);
        color: var(--ww-primary-dark);
        letter-spacing: -0.02em;
        line-height: 1.1;
      }
      .wwa-subtitle {
        color: var(--ww-text-sec);
        font-size: var(--ww-type-body-size);
        font-weight: var(--ww-type-secondary-weight);
        max-width: 72ch;
      }
      .wwa-page-header__meta {
        display: flex;
        align-items: center;
        flex-wrap: wrap;
        gap: 10px;
        font-size: var(--ww-type-secondary-size);
        font-weight: var(--ww-type-secondary-weight);
        color: var(--ww-text-sec);
      }
      .wwa-header-actions {
        display: flex;
        align-items: center;
        justify-content: flex-end;
        gap: 12px;
        flex-wrap: wrap;
        margin-left: auto;
      }

      .wwa-toolbar {
        display: flex;
        align-items: center;
        gap: 12px;
        flex-wrap: wrap;
        margin-bottom: var(--ww-space-5);
      }
      .wwa-search { flex: 1; min-width: 220px; }

      .wwa-input, .wwa-select, .wwa-search input {
        width: 100%;
        min-height: var(--ww-control-height);
        padding: 9px 14px;
        border-radius: var(--ww-radius-control);
        border: 1px solid var(--ww-border);
        font-size: var(--ww-type-body-size);
        outline: none;
        font-family: inherit;
        color: var(--ww-text);
        background: var(--ww-card);
        transition: border-color 0.15s ease, box-shadow 0.15s ease, background 0.15s ease;
      }
      .wwa-input:hover, .wwa-select:hover, .wwa-search input:hover {
        border-color: var(--ww-primary);
      }
      .wwa-input:focus-visible, .wwa-select:focus-visible, .wwa-search input:focus-visible {
        border-color: var(--ww-primary);
        box-shadow: 0 0 0 3px var(--ww-focus-ring);
      }
      .wwa-input::placeholder { color: var(--ww-text-sec); }
      .wwa-input-sm { width: 110px; text-align: right; padding: 8px 12px; }

      .wwa-pill-group { display: flex; gap: 8px; flex-wrap: wrap; margin-bottom: 20px; }
      .wwa-pill {
        padding: 8px 16px;
        border-radius: 999px;
        font-size: var(--ww-type-table-body-size);
        font-weight: 600;
        border: 1px solid var(--ww-border);
        background: var(--ww-card);
        color: var(--ww-text-sec);
        cursor: pointer;
        font-family: inherit;
        transition: all 0.15s ease;
      }
      .wwa-pill:hover { border-color: var(--ww-primary); color: var(--ww-primary-dark); background: var(--ww-hover); }
      .wwa-pill:focus-visible { border-color: var(--ww-primary); box-shadow: 0 0 0 3px var(--ww-focus-ring); }
      .wwa-pill-active, .wwa-pill-active:hover {
        background: var(--ww-primary);
        border-color: var(--ww-primary);
        color: var(--ww-card);
      }

      .wwa-select-inline { width: auto; min-width: 150px; flex: 0 0 auto; }
      .wwa-toolbar-count {
        font-size: var(--ww-type-secondary-size);
        font-weight: var(--ww-type-secondary-weight);
        color: var(--ww-text-sec);
        white-space: nowrap;
      }

      .wwa-panel {
        background: var(--ww-card);
        border-radius: var(--ww-radius-card);
        padding: 24px;
        border: 1px solid var(--ww-divider);
        box-shadow: var(--ww-shadow-sm);
        margin-bottom: 24px;
      }
      .wwa-panel:last-child { margin-bottom: 0; }
      .wwa-panel-title {
        font-size: var(--ww-type-card-title-size);
        font-weight: var(--ww-type-card-title-weight);
        color: var(--ww-text);
        margin-bottom: 4px;
      }
      .wwa-panel-subtitle {
        font-size: var(--ww-type-secondary-size);
        font-weight: var(--ww-type-secondary-weight);
        color: var(--ww-text-sec);
        margin-bottom: 18px;
      }

      .wwa-table-wrap {
        background: var(--ww-card);
        border-radius: var(--ww-radius-card);
        border: 1px solid var(--ww-divider);
        box-shadow: var(--ww-shadow-sm);
        overflow: hidden;
        overflow-x: auto;
      }
      .wwa-table {
        width: 100%;
        border-collapse: collapse;
        font-size: var(--ww-type-table-body-size);
        min-width: 640px;
      }
      .wwa-table thead tr { background: var(--ww-elevated); border-bottom: 1px solid var(--ww-divider); }
      .wwa-table th {
        padding: 14px 18px;
        text-align: left;
        font-weight: var(--ww-type-table-header-weight);
        color: var(--ww-text-sec);
        font-size: var(--ww-type-table-header-size);
        text-transform: uppercase;
        letter-spacing: 0.04em;
        white-space: nowrap;
      }
      .wwa-table td {
        min-height: var(--ww-table-row-height);
        padding: 14px 18px;
        border-bottom: 1px solid var(--ww-divider);
        color: var(--ww-text);
        vertical-align: middle;
        font-size: var(--ww-type-table-body-size);
        font-weight: var(--ww-type-table-body-weight);
      }
      .wwa-table tbody tr { transition: background 0.12s ease; }
      .wwa-table tbody tr:hover { background: var(--ww-hover); }
      .wwa-table tbody tr:last-child td { border-bottom: none; }
      .wwa-cell-primary { font-weight: 600; color: var(--ww-text); }
      .wwa-cell-muted {
        color: var(--ww-text-sec);
        font-size: var(--ww-type-secondary-size);
        font-weight: var(--ww-type-secondary-weight);
        margin-top: 2px;
      }
      .wwa-cell-actions { display: flex; gap: 8px; flex-wrap: wrap; }

      .wwa-row-card {
        background: var(--ww-card);
        border-radius: var(--ww-radius-card);
        padding: 18px 20px;
        border: 1px solid var(--ww-divider);
        box-shadow: var(--ww-shadow-sm);
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 16px;
        flex-wrap: wrap;
        transition: box-shadow 0.15s ease;
        margin-bottom: 12px;
      }
      .wwa-row-card:last-child { margin-bottom: 0; }
      .wwa-row-card:hover { box-shadow: var(--ww-shadow-md); }
      .wwa-row-title { font-weight: 700; font-size: var(--ww-type-card-title-size); color: var(--ww-text); }
      .wwa-row-sub { font-size: var(--ww-type-body-size); color: var(--ww-text-sec); margin-top: 4px; }
      .wwa-row-meta { font-size: var(--ww-type-secondary-size); color: var(--ww-text-sec); margin-top: 4px; }
      .wwa-row-actions { display: flex; align-items: center; gap: 10px; flex-wrap: wrap; }
      .wwa-row-list { display: flex; flex-direction: column; }

      .wwa-btn {
        min-height: var(--ww-control-height);
        display: inline-flex;
        align-items: center;
        justify-content: center;
        gap: 8px;
        padding: 10px 20px;
        border-radius: var(--ww-radius-control);
        border: 1px solid transparent;
        font-size: var(--ww-type-body-size);
        font-weight: 600;
        cursor: pointer;
        font-family: inherit;
        line-height: 1;
        transition: background 0.12s ease, border-color 0.12s ease, color 0.12s ease, box-shadow 0.12s ease, opacity 0.12s ease;
        white-space: nowrap;
      }
      .wwa-btn:hover { box-shadow: var(--ww-shadow-sm); }
      .wwa-btn:focus-visible { box-shadow: 0 0 0 3px var(--ww-focus-ring); }
      .wwa-btn:disabled { opacity: 0.6; cursor: not-allowed; transform: none; box-shadow: none; }
      .wwa-btn-sm {
        min-height: var(--ww-control-height-dense);
        padding: 7px 14px;
        border-radius: 8px;
        font-size: var(--ww-type-secondary-size);
      }
      .wwa-btn-icon {
        width: 36px;
        min-width: 36px;
        min-height: 36px;
        padding: 0;
        border-radius: 10px;
      }
      .wwa-btn-primary { background: var(--ww-primary); color: var(--ww-card); }
      .wwa-btn-primary:hover { background: #5f73e3; }
      .wwa-btn-success { background: var(--ww-success); color: var(--ww-card); }
      .wwa-btn-danger-solid { background: var(--ww-danger); color: var(--ww-card); }
      .wwa-btn-secondary { background: var(--ww-card); color: var(--ww-text); border: 1px solid var(--ww-border); }
      .wwa-btn-secondary:hover { border-color: var(--ww-primary); background: var(--ww-hover); }
      .wwa-btn-ghost { background: transparent; color: var(--ww-text); }
      .wwa-btn-ghost:hover { background: var(--ww-hover); color: var(--ww-primary-dark); }
      .wwa-btn-danger {
        background: var(--ww-danger-bg);
        border-color: color-mix(in srgb, var(--ww-danger) 16%, transparent);
        color: var(--ww-danger);
      }
      .wwa-btn-danger:hover { background: #fecaca; }
      .wwa-btn-success-soft { background: var(--ww-success-bg); color: var(--ww-success); }
      .wwa-btn-brand-soft { background: var(--ww-chip-bg); color: var(--ww-primary-dark); }
      .wwa-btn-brand-soft:hover,
      .wwa-btn-success-soft:hover {
        filter: brightness(0.98);
      }

      .wwa-empty {
        text-align: center;
        padding: 56px 24px;
        color: var(--ww-text-sec);
        font-size: var(--ww-type-body-size);
      }
      .wwa-empty-icon { font-size: 30px; margin-bottom: 10px; opacity: 0.6; }
      .wwa-empty-title { font-weight: 600; color: var(--ww-text); margin-bottom: 4px; font-size: var(--ww-type-body-size); }

      .wwa-skeleton {
        border-radius: var(--ww-radius-card);
        background: linear-gradient(90deg, var(--ww-elevated) 25%, var(--ww-bg) 37%, var(--ww-elevated) 63%);
        background-size: 400% 100%;
        animation: wwa-shimmer 1.4s ease infinite;
      }
      @keyframes wwa-shimmer {
        0% { background-position: 100% 50%; }
        100% { background-position: 0 50%; }
      }

      .wwa-status-pill {
        display: inline-flex;
        align-items: center;
        gap: 6px;
        font-size: var(--ww-type-table-body-size);
        font-weight: 600;
        color: var(--ww-success);
        background: var(--ww-success-bg);
        padding: 6px 12px;
        border-radius: 999px;
        white-space: nowrap;
      }
      .wwa-status-dot { width: 6px; height: 6px; border-radius: 50%; background: var(--ww-success); }

      .wwa-alert-error {
        background: var(--ww-danger-bg);
        color: var(--ww-danger);
        padding: 10px 14px;
        border: 1px solid color-mix(in srgb, var(--ww-danger) 18%, transparent);
        border-radius: var(--ww-radius-control);
        font-size: var(--ww-type-table-body-size);
        font-weight: 500;
      }

      .wwa-badge {
        display: inline-flex;
        align-items: center;
        justify-content: center;
        min-height: 24px;
        padding: 4px 10px;
        border-radius: 999px;
        border: 1px solid transparent;
        font-size: var(--ww-type-secondary-size);
        font-weight: 600;
        line-height: 1;
        white-space: nowrap;
      }
      .wwa-badge-sm {
        min-height: 20px;
        padding: 2px 8px;
        font-size: var(--ww-type-caption-size);
      }
      .wwa-badge-success {
        background: var(--ww-success-bg);
        border-color: color-mix(in srgb, var(--ww-success) 14%, transparent);
        color: #166534;
      }
      .wwa-badge-danger {
        background: var(--ww-danger-bg);
        border-color: color-mix(in srgb, var(--ww-danger) 14%, transparent);
        color: #b91c1c;
      }
      .wwa-badge-warning {
        background: var(--ww-warning-bg);
        border-color: color-mix(in srgb, var(--ww-warning) 14%, transparent);
        color: #92400E;
      }
      .wwa-badge-brand {
        background: var(--ww-chip-bg);
        border-color: color-mix(in srgb, var(--ww-primary) 14%, transparent);
        color: var(--ww-primary-dark);
      }
      .wwa-badge-neutral {
        background: var(--ww-elevated);
        border-color: var(--ww-divider);
        color: var(--ww-text-sec);
      }

      .wwa-switch { position: relative; display: inline-block; width: 42px; height: 24px; flex-shrink: 0; }
      .wwa-switch input { opacity: 0; width: 0; height: 0; position: absolute; }
      .wwa-switch-track { position: absolute; inset: 0; background: var(--ww-border); border-radius: 999px; transition: background 0.15s ease; cursor: pointer; }
      .wwa-switch-track::before {
        content: '';
        position: absolute;
        width: 18px;
        height: 18px;
        left: 3px;
        top: 3px;
        background: var(--ww-card);
        border-radius: 50%;
        transition: transform 0.15s ease;
        box-shadow: 0 1px 2px rgba(0, 0, 0, 0.15);
      }
      .wwa-switch input:checked + .wwa-switch-track { background: var(--ww-primary); }
      .wwa-switch input:checked + .wwa-switch-track::before { transform: translateX(18px); }
      .wwa-switch input:focus-visible + .wwa-switch-track { box-shadow: 0 0 0 3px var(--ww-focus-ring); }
      .wwa-switch input:disabled + .wwa-switch-track { opacity: 0.5; cursor: not-allowed; }

      .wwa-setting-row {
        display: flex;
        justify-content: space-between;
        align-items: center;
        padding: 16px 0;
        border-bottom: 1px solid var(--ww-divider);
        gap: 16px;
        flex-wrap: wrap;
      }
      .wwa-setting-row:last-child { border-bottom: none; }
      .wwa-setting-label { font-size: var(--ww-type-body-size); font-weight: 600; color: var(--ww-text); }
      .wwa-setting-sub { font-size: var(--ww-type-secondary-size); color: var(--ww-text-sec); margin-top: 2px; }

      .wwa-form-grid {
        display: grid;
        grid-template-columns: repeat(auto-fit, minmax(220px, 1fr));
        gap: 14px;
        margin-bottom: 16px;
      }
      .wwa-field-label {
        font-size: var(--ww-type-label-size);
        font-weight: var(--ww-type-label-weight);
        color: var(--ww-text-sec);
        display: block;
        margin-bottom: 6px;
      }
      .wwa-field-full { grid-column: 1 / -1; }

      .wwa-stats-grid {
        display: grid;
        grid-template-columns: repeat(auto-fit, minmax(220px, 1fr));
        gap: 20px;
      }
      .wwa-stat-card {
        background: var(--ww-card);
        border-radius: var(--ww-radius-card);
        padding: 20px 22px;
        border: 1px solid var(--ww-divider);
        border-top: 3px solid var(--accent);
        box-shadow: var(--ww-shadow-sm);
        display: flex;
        flex-direction: column;
        gap: 8px;
        transition: transform 0.15s ease, box-shadow 0.15s ease;
      }
      .wwa-stat-card:hover { transform: translateY(-3px); box-shadow: var(--ww-shadow-md); }
      .wwa-stat-top { display: flex; align-items: center; justify-content: space-between; }
      .wwa-stat-title {
        font-size: var(--ww-type-table-header-size);
        font-weight: var(--ww-type-table-header-weight);
        color: var(--ww-text-sec);
        text-transform: uppercase;
        letter-spacing: 0.05em;
      }
      .wwa-stat-icon {
        width: 32px;
        height: 32px;
        border-radius: 9px;
        background: var(--accent-light);
        display: flex;
        align-items: center;
        justify-content: center;
        font-size: 15px;
        flex-shrink: 0;
      }
      .wwa-stat-value { font-size: var(--ww-type-kpi-size); font-weight: var(--ww-type-kpi-weight); color: var(--ww-primary-dark); line-height: 1; }

      .wwa-table tbody tr.wwa-row-selected { background: var(--ww-selected); }
      .wwa-table tbody tr.wwa-row-selected:hover { background: var(--ww-selected); }

      .wwa-split-layout { display: flex; gap: 24px; align-items: flex-start; }
      .wwa-split-main { flex: 1; min-width: 0; }
      .wwa-split-side { width: var(--ww-drawer-width); flex-shrink: 0; }
      .wwa-split-side-wide { width: var(--ww-drawer-width-wide); }

      .wwa-panel-close {
        width: 28px;
        height: 28px;
        border-radius: 8px;
        border: 1px solid transparent;
        background: var(--ww-elevated);
        color: var(--ww-text-sec);
        font-size: 14px;
        line-height: 1;
        cursor: pointer;
        display: flex;
        align-items: center;
        justify-content: center;
        flex-shrink: 0;
        font-family: inherit;
        transition: background 0.15s ease, color 0.15s ease, border-color 0.15s ease;
      }
      .wwa-panel-close:hover { background: var(--ww-danger-bg); color: var(--ww-danger); }
      .wwa-panel-close:focus-visible { border-color: var(--ww-primary); box-shadow: 0 0 0 3px var(--ww-focus-ring); }

      .wwa-avatar {
        width: 52px;
        height: 52px;
        border-radius: 50%;
        background: var(--ww-primary);
        color: var(--ww-card);
        display: flex;
        align-items: center;
        justify-content: center;
        font-size: 19px;
        font-weight: 700;
        flex-shrink: 0;
      }

      .wwa-detail-row {
        display: flex;
        justify-content: space-between;
        align-items: center;
        padding: 10px 0;
        border-bottom: 1px solid var(--ww-divider);
        gap: 12px;
      }
      .wwa-detail-row:last-child { border-bottom: none; }
      .wwa-detail-label {
        font-size: var(--ww-type-label-size);
        color: var(--ww-text-sec);
        font-weight: var(--ww-type-label-weight);
        text-transform: uppercase;
        letter-spacing: 0.04em;
        white-space: nowrap;
      }
      .wwa-detail-value { font-size: var(--ww-type-table-body-size); color: var(--ww-text); font-weight: 600; text-align: right; }

      .wwa-charts-grid {
        display: grid;
        grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
        gap: 20px;
        margin-top: 20px;
      }
      .wwa-chart-card {
        background: var(--ww-card);
        border-radius: var(--ww-radius-card);
        padding: 20px 22px;
        border: 1px solid var(--ww-divider);
        box-shadow: var(--ww-shadow-sm);
      }
      .wwa-chart-title { font-size: var(--ww-type-body-size); font-weight: 700; color: var(--ww-text); margin-bottom: 16px; }
      .wwa-chart-body { display: flex; align-items: center; gap: 20px; flex-wrap: wrap; }
      .wwa-chart-center-value { font-size: 22px; font-weight: 700; fill: var(--ww-primary-dark); font-family: inherit; }
      .wwa-chart-center-label {
        font-size: 10px; font-weight: 700; fill: var(--ww-text-sec); text-transform: uppercase;
        letter-spacing: 0.05em; font-family: inherit;
      }
      .wwa-chart-legend { display: flex; flex-direction: column; gap: 10px; flex: 1; min-width: 140px; }
      .wwa-chart-legend-row { display: flex; align-items: center; gap: 8px; font-size: 13px; }
      .wwa-chart-swatch { width: 10px; height: 10px; border-radius: 3px; flex-shrink: 0; }
      .wwa-chart-legend-label { color: var(--ww-text); flex: 1; }
      .wwa-chart-legend-value { color: var(--ww-text); font-weight: 700; white-space: nowrap; }

      .wwa-bar-chart {
        display: flex;
        align-items: flex-end;
        gap: 14px;
        height: 160px;
        padding-top: 20px;
      }
      .wwa-bar-col { display: flex; flex-direction: column; align-items: center; gap: 6px; height: 100%; }
      .wwa-bar-value { font-size: var(--ww-type-secondary-size); font-weight: 700; color: var(--ww-text); }
      .wwa-bar-track {
        width: 28px;
        flex: 1;
        background: var(--ww-elevated);
        border-radius: 6px;
        display: flex;
        align-items: flex-end;
        overflow: hidden;
      }
      .wwa-bar-fill { width: 100%; border-radius: 4px 4px 0 0; transition: height 0.2s ease; }
      .wwa-bar-label { font-size: var(--ww-type-caption-size); color: var(--ww-text-sec); font-weight: 600; }

      .wwa-stat-sub { font-size: var(--ww-type-caption-size); color: var(--ww-text-sec); font-weight: 600; margin-top: -2px; }

      .wwa-insights-grid {
        display: grid;
        grid-template-columns: repeat(auto-fit, minmax(320px, 1fr));
        gap: 20px;
        margin-top: 20px;
      }
      .wwa-insight-row {
        display: flex;
        align-items: flex-start;
        gap: 10px;
        padding: 10px 0;
        border-bottom: 1px solid var(--ww-divider);
        font-size: 13.5px;
        color: var(--ww-text);
        line-height: 1.4;
      }
      .wwa-insight-row:last-child { border-bottom: none; }
      .wwa-insight-icon { flex-shrink: 0; font-size: 14px; }

      .wwa-attention-panel { border-top: 3px solid var(--ww-danger); }
      .wwa-attention-row {
        padding: 10px 0;
        border-bottom: 1px solid color-mix(in srgb, var(--ww-danger) 16%, transparent);
        font-size: 13.5px;
        color: var(--ww-danger);
        line-height: 1.4;
      }
      .wwa-attention-row:last-child { border-bottom: none; }

      .wwa-recent-row {
        display: flex;
        align-items: center;
        gap: 12px;
        padding: 10px 0;
        border-bottom: 1px solid var(--ww-divider);
        font-size: 13px;
      }
      .wwa-recent-row:last-child { border-bottom: none; }
      .wwa-recent-icon { font-size: 14px; flex-shrink: 0; }
      .wwa-recent-text { color: var(--ww-text); flex: 1; min-width: 0; }
      .wwa-recent-date { color: var(--ww-text-sec); font-size: var(--ww-type-secondary-size); white-space: nowrap; flex-shrink: 0; }

      .wwa-session-card {
        border: 1px solid var(--ww-divider);
        border-radius: 12px;
        padding: 12px 14px;
        margin-bottom: 10px;
      }
      .wwa-session-header {
        display: flex;
        align-items: center;
        gap: 8px;
        flex-wrap: wrap;
        font-weight: 700;
        font-size: 13px;
        color: var(--ww-text);
        margin-bottom: 8px;
      }
      .wwa-exercise-row { padding: 8px 0; border-top: 1px solid var(--ww-divider); }
      .wwa-exercise-row:first-child { border-top: none; }
      .wwa-exercise-name {
        display: flex;
        align-items: center;
        gap: 6px;
        font-size: 13px;
        font-weight: 600;
        color: var(--ww-text);
      }
      .wwa-exercise-meta { font-size: 11.5px; color: var(--ww-text-sec); margin-top: 2px; }
      .wwa-exercise-note { font-size: 11.5px; color: var(--ww-text-sec); font-style: italic; margin-top: 2px; }
      .wwa-set-list { display: flex; flex-wrap: wrap; gap: 6px; margin-top: 6px; }
      .wwa-set-chip {
        font-size: 11px;
        background: var(--ww-elevated);
        color: var(--ww-text);
        padding: 3px 8px;
        border-radius: 6px;
        font-weight: 600;
      }

      .wwa-visually-hidden {
        position: absolute;
        width: 1px;
        height: 1px;
        padding: 0;
        margin: -1px;
        overflow: hidden;
        clip: rect(0, 0, 0, 0);
        white-space: nowrap;
        border: 0;
      }

      .wwa-search-input {
        position: relative;
        width: 100%;
        min-width: 0;
      }
      .wwa-search-input__icon {
        position: absolute;
        left: 14px;
        top: 50%;
        transform: translateY(-50%);
        width: 16px;
        height: 16px;
        color: var(--ww-text-sec);
        pointer-events: none;
      }
      .wwa-search-input__control {
        padding-left: 40px !important;
        padding-right: 40px !important;
      }
      .wwa-search-input__clear {
        position: absolute;
        right: 8px;
        top: 50%;
        transform: translateY(-50%);
        width: 28px;
        height: 28px;
        border: 0;
        border-radius: 8px;
        background: transparent;
        color: var(--ww-text-sec);
        display: inline-flex;
        align-items: center;
        justify-content: center;
        cursor: pointer;
        transition: background 0.12s ease, color 0.12s ease;
      }
      .wwa-search-input__clear:hover {
        background: var(--ww-hover);
        color: var(--ww-primary-dark);
      }
      .wwa-search-input__clear:focus-visible {
        box-shadow: 0 0 0 3px var(--ww-focus-ring);
      }

      .wwa-select-field {
        position: relative;
        min-width: 0;
      }
      .wwa-select-field__control {
        width: 100%;
        appearance: none;
        padding-right: 40px !important;
      }
      .wwa-select-field__icon {
        position: absolute;
        right: 14px;
        top: 50%;
        transform: translateY(-50%);
        width: 16px;
        height: 16px;
        color: var(--ww-text-sec);
        pointer-events: none;
      }

      .wwa-filterbar {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: var(--ww-space-4);
        flex-wrap: wrap;
        margin-bottom: var(--ww-space-5);
      }
      .wwa-filterbar__left,
      .wwa-filterbar__right {
        display: flex;
        align-items: center;
        gap: 12px;
        flex-wrap: wrap;
      }
      .wwa-filterbar__left {
        flex: 1 1 640px;
        min-width: min(100%, 360px);
      }
      .wwa-filterbar__right {
        justify-content: flex-end;
        margin-left: auto;
      }
      .wwa-filterbar__search {
        flex: 1 1 320px;
        min-width: min(100%, 280px);
        max-width: 360px;
      }
      .wwa-filterbar__filters {
        display: flex;
        align-items: center;
        gap: 12px;
        flex-wrap: wrap;
      }
      .wwa-filterbar__filters .wwa-select-field,
      .wwa-filterbar__filters .wwa-select-inline,
      .wwa-filterbar__filters > * {
        min-width: 150px;
      }
      .wwa-filterbar__count {
        font-size: var(--ww-type-secondary-size);
        font-weight: var(--ww-type-secondary-weight);
        color: var(--ww-text-sec);
        white-space: nowrap;
      }

      .wwa-data-table {
        background: var(--ww-card);
        border: 1px solid var(--ww-divider);
        border-radius: var(--ww-radius-card);
        box-shadow: var(--ww-shadow-sm);
        overflow: hidden;
      }
      .wwa-data-table__scroll {
        overflow-x: auto;
      }
      .wwa-data-table__table {
        min-width: 100%;
      }
      .wwa-data-table__table td,
      .wwa-data-table__table th {
        height: var(--ww-table-row-height);
      }
      .wwa-data-table-dense .wwa-data-table__table td,
      .wwa-data-table-dense .wwa-data-table__table th {
        height: 44px;
        padding-top: 10px;
        padding-bottom: 10px;
      }
      .wwa-data-table__row-clickable {
        cursor: pointer;
      }
      .wwa-data-table__row-clickable:focus-visible {
        outline: 2px solid var(--ww-primary);
        outline-offset: -2px;
      }
      .wwa-data-table__actions {
        display: flex;
        justify-content: flex-end;
      }
      .wwa-data-table__empty-cell {
        padding: 0 !important;
      }
      .wwa-data-table__loading-row:hover {
        background: transparent !important;
      }
      .wwa-data-table__cell-skeleton {
        height: 14px;
        border-radius: 999px;
      }
      .wwa-data-table__action-skeleton {
        width: 32px;
        height: 32px;
        border-radius: 10px;
        margin-left: auto;
      }
      .wwa-table-align-right {
        text-align: right !important;
      }

      .wwa-table-actions {
        position: relative;
        display: inline-flex;
      }
      .wwa-table-actions__trigger {
        color: var(--ww-text-sec);
      }
      .wwa-table-actions__menu {
        position: absolute;
        top: calc(100% + 8px);
        right: 0;
        min-width: 180px;
        padding: 8px;
        border-radius: 12px;
        border: 1px solid var(--ww-divider);
        background: var(--ww-card);
        box-shadow: var(--ww-shadow-md);
        z-index: 30;
      }
      .wwa-table-actions__item {
        width: 100%;
        border: 0;
        border-radius: 8px;
        background: transparent;
        color: var(--ww-text);
        min-height: 36px;
        padding: 8px 10px;
        display: flex;
        align-items: center;
        gap: 8px;
        text-align: left;
        font-size: var(--ww-type-table-body-size);
        font-weight: 500;
        cursor: pointer;
        transition: background 0.12s ease, color 0.12s ease;
      }
      .wwa-table-actions__item:hover {
        background: var(--ww-hover);
      }
      .wwa-table-actions__item:focus-visible {
        box-shadow: 0 0 0 3px var(--ww-focus-ring);
      }
      .wwa-table-actions__item:disabled {
        color: var(--ww-text-sec);
        cursor: not-allowed;
        opacity: 0.65;
      }
      .wwa-table-actions__item.is-danger {
        color: var(--ww-danger);
      }
      .wwa-table-actions__item.is-danger:hover {
        background: var(--ww-danger-bg);
      }
      .wwa-table-actions__item-icon {
        display: inline-flex;
        align-items: center;
        justify-content: center;
        color: inherit;
        flex-shrink: 0;
      }
      .wwa-table-actions__divider {
        height: 1px;
        background: var(--ww-divider);
        margin: 6px 0;
      }

      .wwa-detail-drawer {
        width: var(--ww-drawer-width);
        max-width: 100%;
        border: 1px solid var(--ww-divider);
        border-radius: var(--ww-radius-dialog);
        background: var(--ww-card);
        box-shadow: var(--ww-shadow-sm);
        display: flex;
        flex-direction: column;
        overflow: hidden;
      }
      .wwa-detail-drawer-viewport-locked {
        position: sticky;
        top: var(--ww-space-4);
        max-height: calc(100vh - (var(--ww-space-4) * 2));
      }
      .wwa-detail-drawer-wide {
        width: var(--ww-drawer-width-wide);
      }
      .wwa-detail-drawer__header,
      .wwa-detail-drawer__footer {
        display: flex;
        align-items: flex-start;
        justify-content: space-between;
        gap: 12px;
        padding: 18px 20px;
        background: var(--ww-card);
      }
      .wwa-detail-drawer__header {
        border-bottom: 1px solid var(--ww-divider);
        position: sticky;
        top: 0;
        z-index: 1;
      }
      .wwa-detail-drawer__footer {
        border-top: 1px solid var(--ww-divider);
        position: sticky;
        bottom: 0;
      }
      .wwa-detail-drawer__header-main {
        display: flex;
        align-items: flex-start;
        justify-content: space-between;
        gap: 12px;
        flex: 1;
        min-width: 0;
      }
      .wwa-detail-drawer__title {
        font-size: var(--ww-type-section-title-size);
        font-weight: var(--ww-type-section-title-weight);
        color: var(--ww-primary-dark);
        line-height: 1.2;
      }
      .wwa-detail-drawer__header-actions,
      .wwa-detail-drawer__footer {
        display: flex;
        align-items: center;
        gap: 10px;
        flex-wrap: wrap;
      }
      .wwa-detail-drawer__summary {
        padding: 18px 20px;
        border-bottom: 1px solid var(--ww-divider);
        background: color-mix(in srgb, var(--ww-elevated) 55%, var(--ww-card));
      }
      .wwa-detail-drawer__body {
        padding: 20px;
        overflow-y: auto;
        display: flex;
        flex-direction: column;
        gap: 20px;
        min-height: 0;
      }

      .wwa-form-section {
        background: var(--ww-card);
        border: 1px solid var(--ww-divider);
        border-radius: var(--ww-radius-card);
        padding: 20px;
      }
      .wwa-form-section__header {
        margin-bottom: 16px;
      }
      .wwa-form-section__title {
        font-size: var(--ww-type-section-title-size);
        font-weight: var(--ww-type-section-title-weight);
        color: var(--ww-primary-dark);
        line-height: 1.2;
      }
      .wwa-form-section__description {
        font-size: var(--ww-type-secondary-size);
        font-weight: var(--ww-type-secondary-weight);
        color: var(--ww-text-sec);
        margin-top: 6px;
        max-width: 72ch;
      }
      .wwa-form-section__content {
        display: grid;
        gap: 16px;
      }
      .wwa-form-section__content-two {
        grid-template-columns: repeat(2, minmax(0, 1fr));
      }
      .wwa-form-section__content-one {
        grid-template-columns: minmax(0, 1fr);
      }

      .wwa-form-field {
        min-width: 0;
      }
      .wwa-form-field-full {
        grid-column: 1 / -1;
      }
      .wwa-form-field__label-row {
        display: flex;
        align-items: baseline;
        justify-content: space-between;
        gap: 12px;
        margin-bottom: 6px;
      }
      .wwa-form-field__label {
        font-size: var(--ww-type-label-size);
        font-weight: var(--ww-type-label-weight);
        color: var(--ww-text);
      }
      .wwa-form-field__meta,
      .wwa-form-field__help {
        font-size: var(--ww-type-secondary-size);
        font-weight: var(--ww-type-secondary-weight);
        color: var(--ww-text-sec);
      }
      .wwa-form-field__control {
        min-width: 0;
      }
      .wwa-form-field__help,
      .wwa-form-field__error {
        margin-top: 6px;
      }
      .wwa-form-field__error {
        color: var(--ww-danger);
        font-size: var(--ww-type-secondary-size);
        font-weight: 600;
      }
      .wwa-help-text {
        font-size: var(--ww-type-secondary-size);
        font-weight: var(--ww-type-secondary-weight);
        color: var(--ww-text-sec);
      }

      .wwa-tag-editor {
        display: flex;
        flex-direction: column;
        gap: 10px;
      }
      .wwa-tag-editor__chips {
        display: flex;
        flex-wrap: wrap;
        gap: 8px;
      }
      .wwa-tag-editor__chip {
        display: inline-flex;
        align-items: center;
        gap: 6px;
      }
      .wwa-tag-editor__remove {
        border: 0;
        background: transparent;
        color: var(--ww-text-sec);
        display: inline-flex;
        align-items: center;
        justify-content: center;
        width: 16px;
        height: 16px;
        padding: 0;
        cursor: pointer;
        transition: color 0.12s ease;
      }
      .wwa-tag-editor__remove:hover {
        color: var(--ww-danger);
      }
      .wwa-tag-editor__remove:focus-visible {
        box-shadow: 0 0 0 3px var(--ww-focus-ring);
        border-radius: 999px;
      }
      .wwa-tag-editor__input-row {
        display: flex;
        gap: 8px;
        align-items: flex-start;
      }
      .wwa-tag-editor__input-row .wwa-input {
        flex: 1;
      }

      .wwa-check-grid {
        display: grid;
        grid-template-columns: repeat(auto-fit, minmax(180px, 1fr));
        gap: 10px 14px;
      }
      .wwa-check-item {
        display: flex;
        align-items: flex-start;
        gap: 10px;
        min-height: 40px;
        padding: 10px 12px;
        border: 1px solid var(--ww-divider);
        border-radius: 12px;
        background: var(--ww-card);
        color: var(--ww-text);
        font-size: var(--ww-type-table-body-size);
      }
      .wwa-check-item input {
        margin-top: 2px;
        flex-shrink: 0;
      }
      .wwa-check-item--checked {
        border-color: var(--ww-chip-bg);
        background: var(--ww-hover);
      }

      .wwa-step-editor {
        display: flex;
        flex-direction: column;
        gap: 12px;
      }
      .wwa-step-editor__row {
        display: grid;
        grid-template-columns: 32px minmax(0, 1fr) auto auto;
        gap: 10px;
        align-items: flex-start;
        padding: 12px;
        border: 1px solid var(--ww-divider);
        border-radius: 12px;
        background: var(--ww-card);
      }
      .wwa-step-editor__number {
        display: inline-flex;
        align-items: center;
        justify-content: center;
        min-height: 36px;
        font-size: var(--ww-type-table-header-size);
        font-weight: var(--ww-type-table-header-weight);
        color: var(--ww-text-sec);
      }
      .wwa-step-editor__textarea {
        min-height: 90px;
        resize: vertical;
      }
      .wwa-step-editor__controls {
        display: flex;
        flex-direction: column;
        gap: 6px;
      }
      .wwa-step-editor__controls .wwa-btn,
      .wwa-step-editor__remove {
        min-width: 36px;
      }
      .wwa-step-editor__footer {
        display: flex;
        justify-content: flex-start;
      }

      .wwa-detail-summary {
        display: flex;
        gap: 16px;
        align-items: flex-start;
      }
      .wwa-detail-summary__media {
        width: 112px;
        height: 112px;
        border-radius: 12px;
        background: var(--ww-elevated);
        border: 1px solid var(--ww-divider);
        overflow: hidden;
        display: flex;
        align-items: center;
        justify-content: center;
        flex-shrink: 0;
      }
      .wwa-detail-summary__media img {
        width: 100%;
        height: 100%;
        object-fit: contain;
      }
      .wwa-detail-summary__placeholder {
        padding: 12px;
        text-align: center;
        color: var(--ww-text-sec);
        font-size: var(--ww-type-secondary-size);
      }
      .wwa-detail-summary__content {
        display: flex;
        flex-direction: column;
        gap: 10px;
        min-width: 0;
      }
      .wwa-detail-summary__title {
        font-size: var(--ww-type-section-title-size);
        font-weight: var(--ww-type-section-title-weight);
        color: var(--ww-primary-dark);
        line-height: 1.2;
      }
      .wwa-detail-summary__meta {
        display: flex;
        flex-wrap: wrap;
        gap: 8px;
      }
      .wwa-detail-section {
        display: flex;
        flex-direction: column;
        gap: 12px;
      }
      .wwa-detail-section + .wwa-detail-section {
        padding-top: 20px;
        border-top: 1px solid var(--ww-divider);
      }
      .wwa-detail-section__title {
        font-size: var(--ww-type-table-header-size);
        font-weight: var(--ww-type-table-header-weight);
        color: var(--ww-text-sec);
        text-transform: uppercase;
        letter-spacing: 0.05em;
      }
      .wwa-chip-list {
        display: flex;
        flex-wrap: wrap;
        gap: 8px;
      }
      .wwa-detail-list {
        margin: 0;
        padding-left: 18px;
        display: flex;
        flex-direction: column;
        gap: 8px;
        color: var(--ww-text);
        font-size: var(--ww-type-body-size);
        line-height: 1.6;
      }

      .wwa-metric-card {
        background: var(--ww-card);
        border: 1px solid var(--ww-divider);
        border-radius: var(--ww-radius-card);
        padding: 20px;
        box-shadow: var(--ww-shadow-sm);
        display: flex;
        flex-direction: column;
        gap: 10px;
      }
      .wwa-metric-card__top,
      .wwa-metric-card__footer {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 10px;
      }
      .wwa-metric-card__label {
        font-size: var(--ww-type-table-header-size);
        font-weight: var(--ww-type-table-header-weight);
        text-transform: uppercase;
        letter-spacing: 0.05em;
        color: var(--ww-text-sec);
      }
      .wwa-metric-card__icon {
        width: 32px;
        height: 32px;
        border-radius: 10px;
        background: var(--ww-elevated);
        color: var(--ww-primary-dark);
        display: inline-flex;
        align-items: center;
        justify-content: center;
        flex-shrink: 0;
      }
      .wwa-metric-card__value {
        font-size: var(--ww-type-kpi-size);
        font-weight: var(--ww-type-kpi-weight);
        color: var(--ww-primary-dark);
        line-height: 1;
      }
      .wwa-metric-card__meta {
        font-size: var(--ww-type-secondary-size);
        font-weight: var(--ww-type-secondary-weight);
        color: var(--ww-text-sec);
      }
      .wwa-metric-card__status {
        display: inline-flex;
        align-items: center;
        justify-content: center;
        min-height: 22px;
        padding: 3px 8px;
        border-radius: 999px;
        font-size: var(--ww-type-caption-size);
        font-weight: 700;
        border: 1px solid transparent;
      }
      .wwa-metric-card__status-neutral {
        background: var(--ww-elevated);
        color: var(--ww-text-sec);
        border-color: var(--ww-divider);
      }
      .wwa-metric-card__status-success {
        background: var(--ww-success-bg);
        color: #166534;
        border-color: color-mix(in srgb, var(--ww-success) 14%, transparent);
      }
      .wwa-metric-card__status-warning {
        background: var(--ww-warning-bg);
        color: #92400E;
        border-color: color-mix(in srgb, var(--ww-warning) 14%, transparent);
      }
      .wwa-metric-card__status-danger {
        background: var(--ww-danger-bg);
        color: #b91c1c;
        border-color: color-mix(in srgb, var(--ww-danger) 14%, transparent);
      }
      .wwa-metric-card__status-brand {
        background: var(--ww-chip-bg);
        color: var(--ww-primary-dark);
        border-color: color-mix(in srgb, var(--ww-primary) 14%, transparent);
      }

      .wwa-loading-state {
        display: flex;
        flex-direction: column;
        gap: 8px;
        padding: 20px;
        border: 1px solid var(--ww-divider);
        border-radius: var(--ww-radius-card);
        background: var(--ww-card);
      }
      .wwa-loading-state__title {
        font-size: var(--ww-type-card-title-size);
        font-weight: var(--ww-type-card-title-weight);
        color: var(--ww-text);
      }
      .wwa-loading-state__message {
        font-size: var(--ww-type-secondary-size);
        font-weight: var(--ww-type-secondary-weight);
        color: var(--ww-text-sec);
      }
      .wwa-loading-state__rows {
        display: grid;
        gap: 10px;
      }
      .wwa-loading-state__row {
        border-radius: 10px;
      }

      .wwa-error-state {
        display: flex;
        align-items: flex-start;
        gap: 12px;
        padding: 14px 16px;
        border: 1px solid color-mix(in srgb, var(--ww-danger) 16%, transparent);
        border-radius: var(--ww-radius-card);
        background: var(--ww-card);
      }
      .wwa-error-state__icon {
        width: 28px;
        height: 28px;
        border-radius: 999px;
        background: var(--ww-danger-bg);
        color: var(--ww-danger);
        display: inline-flex;
        align-items: center;
        justify-content: center;
        flex-shrink: 0;
      }
      .wwa-error-state__content {
        flex: 1;
        min-width: 0;
      }
      .wwa-error-state__title {
        font-size: var(--ww-type-body-size);
        font-weight: 700;
        color: var(--ww-text);
      }
      .wwa-error-state__message {
        font-size: var(--ww-type-secondary-size);
        font-weight: var(--ww-type-secondary-weight);
        color: var(--ww-text-sec);
        margin-top: 4px;
      }

      @media (max-width: 640px) {
        .wwa-row-card { flex-direction: column; align-items: flex-start; }
        .wwa-row-actions { width: 100%; }
        .wwa-table { min-width: 560px; }
        .wwa-recent-row { flex-wrap: wrap; }
        .wwa-recent-date { margin-left: 26px; }
        .wwa-filterbar__search {
          min-width: 100%;
          max-width: none;
        }
        .wwa-form-section__content-two {
          grid-template-columns: minmax(0, 1fr);
        }
        .wwa-step-editor__row {
          grid-template-columns: 32px minmax(0, 1fr);
        }
        .wwa-step-editor__controls {
          flex-direction: row;
          grid-column: 2;
        }
        .wwa-step-editor__remove {
          grid-column: 2;
        }
        .wwa-tag-editor__input-row {
          flex-direction: column;
        }
        .wwa-detail-summary {
          flex-direction: column;
        }
      }
      @media (max-width: 900px) {
        .wwa-split-layout { flex-direction: column; }
        .wwa-split-side, .wwa-split-side-wide { width: 100%; }
        .wwa-detail-drawer,
        .wwa-detail-drawer-wide,
        .wwa-detail-drawer-viewport-locked {
          width: 100%;
          max-height: none;
          position: static;
        }
        .wwa-filterbar__left,
        .wwa-filterbar__right {
          flex: 1 1 100%;
          width: 100%;
          margin-left: 0;
          justify-content: flex-start;
        }
      }
      @media (max-width: 480px) {
        .wwa-title { font-size: 22px; }
        .wwa-panel { padding: 18px; }
        .wwa-detail-drawer__header,
        .wwa-detail-drawer__summary,
        .wwa-detail-drawer__body,
        .wwa-detail-drawer__footer,
        .wwa-form-section {
          padding: 16px;
        }
      }
    `}</style>
  );
}

export default AdminStyles;
